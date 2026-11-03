# D1 迁移

`0001_init.sql` 创建样本和同步状态表，只包含结构，无真实数据。

在 `server` 目录执行：

```sh
npx wrangler d1 migrations apply DB --local
npx wrangler d1 migrations apply DB --remote
```

先核对账号及 `DB` 绑定。已应用的迁移不可修改，后续变更增加新的序号文件。正常发布使用 `npm run deploy`，先迁移再部署。
