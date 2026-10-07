use super::*;
use crate::llm::siwc::SiwcHttpClient;
use bytes::Bytes;
use futures::stream;
use rig::http_client::{
    HttpClientExt, LazyBody, MultipartForm, Request, Response, Result as HttpResult,
    StreamingResponse, sse::BoxedStream,
};
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

#[derive(Clone, Debug, Default)]
struct FakeHttp {
    responses: Arc<Mutex<VecDeque<String>>>,
    requests: Arc<Mutex<Vec<Value>>>,
}

impl HttpClientExt for FakeHttp {
    fn send<T, U>(
        &self,
        _: Request<T>,
    ) -> impl Future<Output = HttpResult<Response<LazyBody<U>>>> + WasmCompatSend + 'static
    where
        T: Into<Bytes> + WasmCompatSend,
        U: From<Bytes> + WasmCompatSend + 'static,
    {
        std::future::ready(Err(rig::http_client::Error::StreamEnded))
    }

    fn send_multipart<U>(
        &self,
        _: Request<MultipartForm>,
    ) -> impl Future<Output = HttpResult<Response<LazyBody<U>>>> + WasmCompatSend + 'static
    where
        U: From<Bytes> + WasmCompatSend + 'static,
    {
        std::future::ready(Err(rig::http_client::Error::StreamEnded))
    }

    async fn send_streaming<T>(&self, request: Request<T>) -> HttpResult<StreamingResponse>
    where
        T: Into<Bytes> + WasmCompatSend,
    {
        assert_eq!(request.uri().to_string(), crate::llm::siwc::ENDPOINT);
        let body: Value = serde_json::from_slice(&request.into_body().into()).unwrap();
        self.requests.lock().unwrap().push(body);
        let response = self
            .responses
            .lock()
            .unwrap()
            .pop_front()
            .expect("no automatic retries");
        // The source deliberately stays open after its terminal frame.
        let body: BoxedStream =
            Box::pin(stream::once(async { Ok(Bytes::from(response)) }).chain(stream::pending()));
        Ok(Response::builder().status(200).body(body).unwrap())
    }
}

fn frame(value: Value) -> String {
    format!("data: {value}\n\n")
}

fn terminal(kind: &str, status: &str) -> String {
    frame(json!({
        "type":kind, "sequence_number":10,
        "response": {"id":"resp_test","object":"response","created_at":1,
            "status":status,"model":"test-model","output":[],
            "tools":[{"type":"namespace","name":"selume","description":"Local tools",
                "tools":[{"type":"function","name":"getDiary","parameters":{"type":"object"}}]}],
            "usage":{"input_tokens":5,"output_tokens":3,"total_tokens":8}}
    }))
}

fn tool_turn(kind: &str, status: &str) -> String {
    let item = json!({"type":"function_call","id":"fc_test","call_id":"call_test",
        "name":"getDiary","namespace":"selume","arguments":"{}","status":"completed"});
    let mut added = item.clone();
    added["arguments"] = json!("");
    added["status"] = json!("in_progress");
    frame(
        json!({"type":"response.output_item.done","sequence_number":0,"output_index":0,
        "item":{"type":"reasoning","id":"rs_test","summary":[],"encrypted_content":"encrypted-test"}}),
    ) + &frame(
        json!({"type":"response.output_item.added","sequence_number":1,"output_index":1,
        "item":added}),
    ) + &frame(
        json!({"type":"response.output_item.done","sequence_number":2,"output_index":1,"item":item}),
    ) + &terminal(kind, status)
}

async fn run_tool_case(
    verdict: &'static str,
    first_response: String,
) -> (Result<()>, FakeHttp, usize, usize) {
    run_tool_case_with_emit(verdict, first_response, Arc::new(|_| true)).await
}

async fn run_tool_case_with_emit(
    verdict: &'static str,
    first_response: String,
    emit: EmitFn,
) -> (Result<()>, FakeHttp, usize, usize) {
    let fake = FakeHttp::default();
    fake.responses.lock().unwrap().extend([
        first_response,
        frame(
            json!({"type":"response.output_text.delta","sequence_number":0,
            "item_id":"msg_test","output_index":0,"content_index":0,"delta":"done"}),
        ) + &terminal("response.completed", "completed"),
    ]);
    let client = openai::Client::builder()
        .api_key("fake-token")
        .http_client(SiwcHttpClient::for_test(fake.clone()))
        .build()
        .unwrap()
        .with_system_instructions_placement(
            openai::responses_api::SystemInstructionsPlacement::AllInstructions,
        );
    let dispatched = Arc::new(AtomicUsize::new(0));
    let dispatch_count = dispatched.clone();
    let dispatch: ToolDispatch = Arc::new(move |name, _| {
        assert_eq!(name, "getDiary");
        dispatch_count.fetch_add(1, Ordering::SeqCst);
        Box::pin(async { "diary result".into() })
    });
    let gated = Arc::new(AtomicUsize::new(0));
    let gate_count = gated.clone();
    let gate: ToolGate = Arc::new(move |_, name, _| {
        assert_eq!(name, "getDiary");
        gate_count.fetch_add(1, Ordering::SeqCst);
        Box::pin(async move { verdict.into() })
    });
    let tools = build_tools(
        vec![RigToolDef {
            name: "getDiary".into(),
            description: "Read a diary".into(),
            parameters_json:
                r#"{"type":"object","properties":{},"required":[],"additionalProperties":false}"#
                    .into(),
        }],
        &dispatch,
    );
    let agent = finish(
        client.agent("test-model").preamble("stable instructions"),
        tools,
        &emit,
        &gate,
    );
    let result = tokio::time::timeout(
        Duration::from_secs(2),
        drive(
            agent,
            Message::user("Read it"),
            vec![Message::system("volatile context")],
            &emit,
            3,
        ),
    )
    .await
    .expect("must not wait for EOF");
    (
        result,
        fake,
        gated.load(Ordering::SeqCst),
        dispatched.load(Ordering::SeqCst),
    )
}

#[tokio::test]
async fn siwc_tool_gate_and_replay_preserve_existing_loop() {
    for (verdict, expected_dispatch) in [("run", 1), ("skip:Declined", 0)] {
        let (result, fake, gates, dispatched) =
            run_tool_case(verdict, tool_turn("response.completed", "completed")).await;
        result.unwrap();
        assert_eq!(gates, 1);
        assert_eq!(dispatched, expected_dispatch);
        let requests = fake.requests.lock().unwrap();
        assert_eq!(requests.len(), 2);
        assert!(
            requests[0]["instructions"]
                .as_str()
                .unwrap()
                .contains("volatile context")
        );
        assert_eq!(requests[0]["tools"][0]["type"], "namespace");
        assert!(requests[0].get("max_output_tokens").is_none());
        assert_eq!(
            requests[0]["include"],
            json!(["reasoning.encrypted_content"])
        );
        let input = requests[1]["input"].as_array().unwrap();
        let reasoning = input
            .iter()
            .find(|item| item["type"] == "reasoning")
            .unwrap();
        assert_eq!(reasoning["encrypted_content"], "encrypted-test");
        let call = input
            .iter()
            .find(|item| item["type"] == "function_call")
            .unwrap();
        let output = input
            .iter()
            .find(|item| item["type"] == "function_call_output")
            .unwrap();
        assert_eq!(call["namespace"], "selume");
        assert_eq!(call["call_id"], output["call_id"]);
        assert_eq!(call["call_id"], "call_test");
    }
}

#[tokio::test]
async fn siwc_failed_or_incomplete_turn_never_runs_diary_tools() {
    for (kind, status) in [
        ("response.incomplete", "incomplete"),
        ("response.failed", "failed"),
        ("response.completed", "incomplete"),
    ] {
        let (result, fake, gates, dispatched) = run_tool_case("run", tool_turn(kind, status)).await;
        assert!(result.is_err());
        assert_eq!(gates, 0);
        assert_eq!(dispatched, 0);
        assert_eq!(fake.requests.lock().unwrap().len(), 1);
    }
}

#[tokio::test]
async fn siwc_closed_sink_stops_before_tool_dispatch_or_another_request() {
    let (result, fake, gates, dispatched) = run_tool_case_with_emit(
        "run",
        tool_turn("response.completed", "completed"),
        Arc::new(|_| false),
    )
    .await;
    result.unwrap();
    assert_eq!(gates, 0);
    assert_eq!(dispatched, 0);
    assert_eq!(fake.requests.lock().unwrap().len(), 1);
}
