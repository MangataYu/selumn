# personal 分支旧 v3 数据库

这个夹具保留 `fd465fcb83e1cb64a0aeaf655c9b04668c7bdb52` 中的数据库结构，
用于验证已安装的 personal Debug 版升级到 v4 后仍能读取原数据。
它与上游 `13cee5d` 使用相同的版本号 3，但还没有消息供应商和记忆来源字段，
并且仍包含助手预设。因此不能用上游的 v3 快照替代这个夹具。

`drift_schema_v3.json` 由 drift_dev 2.35.0 从上述提交的
`lib/src/db/database.dart`、`database.g.dart`、`db_codec.dart` 和全部 `.drift`
文件导出，没有手动修改快照。历史源文件放在本包临时目录
`.dart_tool/personal_v3_source/` 后，在本包目录执行：

```sh
dart run drift_dev schema dump .dart_tool/personal_v3_source/database.dart test/fixtures/personal_v3/drift_schema_v3.json
dart run drift_dev schema generate test/fixtures/personal_v3 test/fixtures/personal_v3/generated
```

`generated/` 由第二条命令生成。drift_dev 2.35.0 的测试数据库生成器未包含
快照中的触发器，因此回归测试先通过生成的 schema 建旧库，再从这个冻结快照
恢复触发器，然后写入日记、会话、消息、记忆和预设数据。测试会先确认旧库
已经有全文索引，再验证迁移后的数据与检索结果，不重建索引来补救夹具。
