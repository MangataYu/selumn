//! The public Sign in with ChatGPT HTTP route is a restricted Responses API.
//! Keep Rig's tool runner, but enforce its wire contract before sending credentials.
use std::time::Duration;

use bytes::Bytes;
use futures::{StreamExt, stream};
use rig::http_client::{
    Error, HeaderValue, HttpClientExt, LazyBody, MultipartForm, Request, Response,
    Result as HttpResult, StreamingResponse, sse::BoxedStream,
};
use rig::wasm_compat::WasmCompatSend;
use serde_json::{Value, json};

pub(super) const ENDPOINT: &str = "https://api.openai.com/v1/responses";
const NAMESPACE: &str = "selume";
const MAX_FRAME_BYTES: usize = 2 * 1024 * 1024;
const MAX_RESPONSE_BYTES: usize = 16 * 1024 * 1024;

#[derive(Clone, Debug, Default)]
pub(super) struct SiwcHttpClient<H = reqwest::Client> {
    inner: H,
}

impl SiwcHttpClient {
    pub(super) fn new() -> anyhow::Result<Self> {
        Ok(Self {
            inner: crate::http::client::builder()?
                .redirect(reqwest::redirect::Policy::none())
                .retry(reqwest::retry::never())
                .connect_timeout(Duration::from_secs(30))
                .read_timeout(Duration::from_secs(60))
                .timeout(Duration::from_secs(180))
                .build()?,
        })
    }
}

#[cfg(test)]
impl<H> SiwcHttpClient<H> {
    pub(super) fn for_test(inner: H) -> Self {
        Self { inner }
    }
}

pub(super) fn safe_chat_error(error: anyhow::Error) -> anyhow::Error {
    let message = error.to_string();
    for code in ["max_turns", "cancelled", "unknown_tool"] {
        if message.starts_with(&format!("{code}:")) {
            return anyhow::anyhow!("{code}: ChatGPT request stopped");
        }
    }
    for code in [
        "subscription_sharing_usage_limit_exceeded",
        "subscription_sharing_usage_unavailable",
        "timeout",
        "response_incomplete",
        "response_not_completed",
        "stream_ended_without_completed",
        "invalid_content_type",
        "invalid_tool_namespace",
        "response_too_large",
        "event_too_large",
        "response_failed",
        "invalid_sse",
        "transport_failed",
    ] {
        if message.contains(&format!("chatgpt_subscription: {code}")) {
            return anyhow::anyhow!("completion: chatgpt_subscription: {code}");
        }
    }
    for status in [400, 401, 403, 404, 408, 429, 500, 502, 503, 504] {
        if message.contains(&format!("Invalid status code: {status}")) {
            return anyhow::anyhow!("completion: chatgpt_subscription: http_{status}");
        }
    }
    anyhow::anyhow!("completion: chatgpt_subscription: invalid_response")
}

fn invalid(reason: &'static str) -> Error {
    Error::Instance(std::io::Error::other(format!("chatgpt_subscription: {reason}")).into())
}

// Never surface server bodies, request data, or credentials through bridge errors.
fn safe_transport_error(error: Error) -> Error {
    match error {
        Error::InvalidStatusCode(status)
        | Error::InvalidStatusCodeWithMessage(status, _)
        | Error::InvalidStatusCodeWithDetails { status, .. } => Error::InvalidStatusCode(status),
        Error::Instance(ref source)
            if source
                .downcast_ref::<reqwest::Error>()
                .is_some_and(reqwest::Error::is_timeout) =>
        {
            invalid("timeout")
        }
        _ => invalid("transport_failed"),
    }
}

fn prepare_request<T: Into<Bytes>>(request: Request<T>) -> HttpResult<Request<Bytes>> {
    if request.method() != "POST" || *request.uri() != ENDPOINT {
        return Err(invalid("unsupported_endpoint"));
    }
    let (mut parts, body) = request.into_parts();
    let mut body: Value =
        serde_json::from_slice(&body.into()).map_err(|_| invalid("invalid_request"))?;
    let object = body
        .as_object_mut()
        .ok_or_else(|| invalid("invalid_request"))?;
    object.retain(|key, _| {
        matches!(
            key.as_str(),
            "model" | "input" | "instructions" | "tools" | "tool_choice" | "reasoning" | "include"
        )
    });
    object.insert("store".into(), json!(false));
    object.insert("stream".into(), json!(true));
    object.insert("parallel_tool_calls".into(), json!(false));
    // Stateless tool continuations need encrypted reasoning even when the
    // caller leaves the model's reasoning effort at its default.
    object.insert("include".into(), json!(["reasoning.encrypted_content"]));
    let input = object
        .get_mut("input")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| invalid("input_must_be_array"))?;
    for item in input {
        if item["role"] == "system" {
            item["role"] = json!("developer");
        }
        if item["type"] == "function_call" {
            // Rig 0.42 does not retain this field while replaying tool calls.
            item["namespace"] = json!(NAMESPACE);
        }
    }
    if let Some(tools) = object.remove("tools") {
        let tools = tools.as_array().ok_or_else(|| invalid("invalid_tools"))?;
        if tools.iter().any(|tool| tool["type"] != "function") {
            return Err(invalid("unsupported_tool"));
        }
        if !tools.is_empty() {
            object.insert(
                "tools".into(),
                json!([{
                    "type": "namespace", "name": NAMESPACE,
                    "description": "Tools for the user's local diary and saved memories.",
                    "tools": tools,
                }]),
            );
        }
    }
    if object
        .get("tool_choice")
        .is_some_and(|choice| !matches!(choice.as_str(), Some("auto" | "none" | "required")))
    {
        return Err(invalid("unsupported_tool_choice"));
    }
    parts.headers.remove("content-length");
    parts
        .headers
        .insert("content-type", HeaderValue::from_static("application/json"));
    parts
        .headers
        .insert("accept", HeaderValue::from_static("text/event-stream"));
    let body = serde_json::to_vec(&body).map_err(|_| invalid("invalid_request"))?;
    Ok(Request::from_parts(parts, body.into()))
}

impl<H: HttpClientExt> HttpClientExt for SiwcHttpClient<H> {
    fn send<T, U>(
        &self,
        _request: Request<T>,
    ) -> impl Future<Output = HttpResult<Response<LazyBody<U>>>> + WasmCompatSend + 'static
    where
        T: Into<Bytes> + WasmCompatSend,
        U: From<Bytes> + WasmCompatSend + 'static,
    {
        std::future::ready(Err(invalid("stream_required")))
    }

    fn send_multipart<U>(
        &self,
        _request: Request<MultipartForm>,
    ) -> impl Future<Output = HttpResult<Response<LazyBody<U>>>> + WasmCompatSend + 'static
    where
        U: From<Bytes> + WasmCompatSend + 'static,
    {
        std::future::ready(Err(invalid("unsupported_endpoint")))
    }

    async fn send_streaming<T>(&self, request: Request<T>) -> HttpResult<StreamingResponse>
    where
        T: Into<Bytes> + WasmCompatSend,
    {
        let request = prepare_request(request)?;
        let response = self
            .inner
            .send_streaming(request)
            .await
            .map_err(safe_transport_error)?;
        adapt_response(response)
    }
}

fn adapt_response(response: StreamingResponse) -> HttpResult<StreamingResponse> {
    if response.status() != 200 {
        return Err(Error::InvalidStatusCode(response.status()));
    }
    let (mut parts, body) = response.into_parts();
    if let Some(content_type) = parts.headers.get("content-type") {
        let is_sse = content_type.to_str().ok().is_some_and(|value| {
            value
                .split(';')
                .next()
                .is_some_and(|mime| mime.trim().eq_ignore_ascii_case("text/event-stream"))
        });
        if !is_sse {
            return Err(invalid("invalid_content_type"));
        }
    } else {
        // Some Android proxy paths strip MIME. This is only a parser hint;
        // the same response body still has to pass the strict SSE/terminal guard.
        parts.headers.insert(
            "content-type",
            HeaderValue::from_static("text/event-stream"),
        );
    }
    Ok(Response::from_parts(parts, guarded_stream(body)))
}

struct SseGuard {
    body: BoxedStream,
    chunk: Bytes,
    offset: usize,
    line: Vec<u8>,
    frame: Vec<u8>,
    skip_lf: bool,
    first_line: bool,
    received: usize,
    done: bool,
}

fn guarded_stream(body: BoxedStream) -> BoxedStream {
    let state = SseGuard {
        body,
        chunk: Bytes::new(),
        offset: 0,
        line: Vec::new(),
        frame: Vec::new(),
        skip_lf: false,
        first_line: true,
        received: 0,
        done: false,
    };
    Box::pin(stream::try_unfold(state, |mut state| async move {
        if state.done {
            return Ok(None);
        }
        loop {
            if state.offset == state.chunk.len() {
                state.chunk = match state.body.next().await {
                    Some(Ok(chunk)) => chunk,
                    Some(Err(error)) => return Err(safe_transport_error(error)),
                    None => return Err(invalid("stream_ended_without_completed")),
                };
                state.offset = 0;
                state.received = state.received.saturating_add(state.chunk.len());
                if state.received > MAX_RESPONSE_BYTES {
                    return Err(invalid("response_too_large"));
                }
                if state.chunk.is_empty() {
                    continue;
                }
            }
            let byte = state.chunk[state.offset];
            state.offset += 1;
            if state.skip_lf {
                state.skip_lf = false;
                if byte == b'\n' {
                    continue;
                }
            }
            if byte != b'\r' && byte != b'\n' {
                state.line.push(byte);
                if state.line.len() + state.frame.len() > MAX_FRAME_BYTES {
                    return Err(invalid("event_too_large"));
                }
                continue;
            }
            state.skip_lf = byte == b'\r';
            if state.first_line {
                state.first_line = false;
                if state.line.starts_with(&[0xef, 0xbb, 0xbf]) {
                    state.line.drain(..3);
                }
            }
            let frame_end = state.line.is_empty();
            state.frame.append(&mut state.line);
            state.frame.push(b'\n');
            if frame_end {
                let frame = std::mem::take(&mut state.frame);
                state.done = check_frame(&frame)?;
                // Do not wait for EOF after response.completed (some proxies keep
                // the connection open). Dropping this state also drops the body.
                if state.done {
                    state.body = Box::pin(stream::empty());
                }
                return Ok(Some((Bytes::from(frame), state)));
            }
        }
    }))
}

fn check_function_namespace(item: &Value) -> HttpResult<()> {
    if item["type"] == "function_call" && item["namespace"] != NAMESPACE {
        return Err(invalid("invalid_tool_namespace"));
    }
    Ok(())
}

fn check_frame(frame: &[u8]) -> HttpResult<bool> {
    let text = std::str::from_utf8(frame).map_err(|_| invalid("invalid_sse"))?;
    let mut event = None;
    let mut data = Vec::new();
    for line in text.lines() {
        if let Some(value) = line.strip_prefix("data:") {
            data.push(value.strip_prefix(' ').unwrap_or(value));
        } else if let Some(value) = line.strip_prefix("event:") {
            event = Some(value.strip_prefix(' ').unwrap_or(value));
        } else if !(line.is_empty()
            || line.starts_with(':')
            || line.starts_with("id:")
            || line.starts_with("retry:"))
        {
            return Err(invalid("invalid_sse"));
        }
    }
    if data.is_empty() {
        return Ok(false);
    }
    let value: Value =
        serde_json::from_str(&data.join("\n")).map_err(|_| invalid("invalid_sse_event"))?;
    let kind = value["type"]
        .as_str()
        .ok_or_else(|| invalid("invalid_sse_event"))?;
    if event.is_some_and(|event| event != kind && event != "message") {
        return Err(invalid("invalid_sse_event"));
    }
    check_function_namespace(&value["item"])?;
    match kind {
        "response.completed" => {
            if value["response"]["status"] != "completed" {
                return Err(invalid("response_not_completed"));
            }
            if let Some(output) = value["response"]["output"].as_array() {
                for item in output {
                    check_function_namespace(item)?;
                }
            }
            Ok(true)
        }
        "response.incomplete" => Err(invalid("response_incomplete")),
        "response.failed" | "error" => {
            let code = value["response"]["error"]["code"]
                .as_str()
                .or_else(|| value["code"].as_str());
            Err(invalid(match code {
                Some("subscription_sharing_usage_limit_exceeded") => {
                    "subscription_sharing_usage_limit_exceeded"
                }
                Some("subscription_sharing_usage_unavailable") => {
                    "subscription_sharing_usage_unavailable"
                }
                _ => "response_failed",
            }))
        }
        _ => Ok(false),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::TryStreamExt;
    use std::pin::Pin;
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    };
    use std::task::{Context, Poll};

    struct DropProbe {
        inner: BoxedStream,
        dropped: Arc<AtomicBool>,
    }

    impl futures::Stream for DropProbe {
        type Item = HttpResult<Bytes>;
        fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
            self.inner.as_mut().poll_next(cx)
        }
    }

    impl Drop for DropProbe {
        fn drop(&mut self) {
            self.dropped.store(true, Ordering::SeqCst);
        }
    }

    fn request(body: Value) -> Request<Bytes> {
        Request::post(ENDPOINT)
            .body(Bytes::from(body.to_string()))
            .unwrap()
    }

    fn completed() -> String {
        "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n".into()
    }

    fn body(bytes: Vec<u8>) -> BoxedStream {
        // Single bytes exercise UTF-8, BOM and CRLF split boundaries.
        Box::pin(stream::iter(
            bytes.into_iter().map(|byte| Ok(Bytes::from(vec![byte]))),
        ))
    }

    #[test]
    fn request_enforces_siwc_contract_and_replays_namespaced_tools() {
        let prepared = prepare_request(request(json!({
            "model":"account-model", "store":true, "stream":false,
            "temperature":0.7, "max_output_tokens":200, "previous_response_id":"old",
            "metadata":{"private":"value"}, "truncation":"auto", "background":true,
            "input":[
                {"role":"system","content":"context"},
                {"type":"function_call","call_id":"call1","name":"getDiary","arguments":"{}"},
                {"type":"function_call_output","call_id":"call1","output":"found"},
                {"type":"reasoning","id":"rs_1","encrypted_content":"encrypted","summary":[]}
            ],
            "reasoning":{"effort":"low"}, "include":["reasoning.encrypted_content"],
            "tools":[{"type":"function","name":"getDiary","parameters":{"type":"object"}}]
        })))
        .unwrap();
        let value: Value = serde_json::from_slice(prepared.body()).unwrap();
        assert_eq!(value["store"], false);
        assert_eq!(value["stream"], true);
        assert_eq!(value["parallel_tool_calls"], false);
        for field in [
            "temperature",
            "max_output_tokens",
            "previous_response_id",
            "metadata",
            "truncation",
            "background",
        ] {
            assert!(value.get(field).is_none(), "{field}");
        }
        assert_eq!(value["input"][0]["role"], "developer");
        assert_eq!(value["input"][1]["namespace"], NAMESPACE);
        assert_eq!(value["input"][2]["call_id"], "call1");
        assert_eq!(value["input"][3]["encrypted_content"], "encrypted");
        assert_eq!(value["tools"][0]["type"], "namespace");
        assert_eq!(value["tools"][0]["tools"][0]["name"], "getDiary");
        assert_eq!(value["include"][0], "reasoning.encrypted_content");
    }

    #[test]
    fn rejects_non_official_endpoint_string_input_and_hosted_tools() {
        for endpoint in [
            "http://api.openai.com/v1/responses",
            "https://example.com/v1/responses",
            "https://api.openai.com/v1/responses?redirect=x",
        ] {
            let request = Request::post(endpoint)
                .body(Bytes::from_static(b"{}"))
                .unwrap();
            assert!(prepare_request(request).is_err());
        }
        assert!(prepare_request(request(json!({"input":"hello"}))).is_err());
        assert!(
            prepare_request(request(
                json!({"input":[],"tools":[{"type":"tool_search"}]})
            ))
            .is_err()
        );
    }

    #[tokio::test]
    async fn missing_mime_bom_crlf_sse_completes_without_waiting_for_eof() {
        let bytes = format!(
            "\u{feff}: keepalive\r\n\r\n{}",
            completed().replace('\n', "\r\n")
        )
        .into_bytes();
        let open_body: BoxedStream = Box::pin(body(bytes).chain(stream::pending()));
        let response = Response::builder().status(200).body(open_body).unwrap();
        let response = adapt_response(response).unwrap();
        assert_eq!(response.headers()["content-type"], "text/event-stream");
        let frames = tokio::time::timeout(
            Duration::from_millis(200),
            response.into_body().try_collect::<Vec<_>>(),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(frames.len(), 2);
    }

    #[tokio::test]
    async fn invalid_or_unfinished_bodies_never_succeed() {
        for bytes in [
            "".to_owned(), "<html>blocked</html>\n\n".to_owned(),
            "{\"output\":\"not SSE\"}\n\n".to_owned(),
            "data: [DONE]\n\n".to_owned(),
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n".to_owned(),
            "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"incomplete\"}}\n\n".to_owned(),
            "data: {\"type\":\"response.incomplete\",\"response\":{\"status\":\"completed\"}}\n\n".to_owned(),
            "event: response.failed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n".to_owned(),
        ] {
            assert!(guarded_stream(body(bytes.into_bytes())).try_collect::<Vec<_>>().await.is_err());
        }
    }

    #[test]
    fn explicit_non_sse_mime_is_rejected_even_with_valid_sse_body() {
        for mime in [
            "text/html",
            "application/json",
            "application/octet-stream",
            "",
        ] {
            let response = Response::builder()
                .status(200)
                .header("content-type", mime)
                .body(body(completed().into_bytes()))
                .unwrap();
            assert!(adapt_response(response).is_err());
        }
    }

    #[test]
    fn safe_errors_preserve_actionable_codes_without_server_content() {
        let frame = b"data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\",\"message\":\"private diary and token\"}}}\n\n";
        let error = check_frame(frame).unwrap_err();
        let safe = safe_chat_error(anyhow::anyhow!("completion: {error}"));
        assert!(
            safe.to_string()
                .contains("subscription_sharing_usage_limit_exceeded")
        );
        assert!(!safe.to_string().contains("private"));
        assert_eq!(
            safe_chat_error(anyhow::anyhow!("untrusted private content")).to_string(),
            "completion: chatgpt_subscription: invalid_response"
        );
    }

    #[tokio::test]
    async fn completing_or_cancelling_drops_the_open_network_body() {
        let dropped = Arc::new(AtomicBool::new(false));
        let source: BoxedStream = Box::pin(DropProbe {
            inner: Box::pin(body(completed().into_bytes()).chain(stream::pending())),
            dropped: dropped.clone(),
        });
        let mut guarded = guarded_stream(source);
        guarded.next().await.unwrap().unwrap();
        assert!(dropped.load(Ordering::SeqCst));
        assert!(guarded.next().await.is_none());

        let dropped = Arc::new(AtomicBool::new(false));
        let source: BoxedStream = Box::pin(DropProbe {
            inner: Box::pin(stream::pending()),
            dropped: dropped.clone(),
        });
        assert!(
            tokio::time::timeout(
                Duration::from_millis(10),
                guarded_stream(source).try_collect::<Vec<_>>()
            )
            .await
            .is_err()
        );
        assert!(dropped.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn wrong_namespace_and_oversized_event_are_rejected() {
        assert!(check_frame(b"data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"function_call\",\"namespace\":\"foreign\"}}\n\n").is_err());
        let source: BoxedStream = Box::pin(stream::once(async {
            Ok(Bytes::from(vec![b'x'; MAX_FRAME_BYTES + 1]))
        }));
        let error = guarded_stream(source)
            .try_collect::<Vec<_>>()
            .await
            .unwrap_err();
        assert!(error.to_string().contains("event_too_large"));
    }
}
