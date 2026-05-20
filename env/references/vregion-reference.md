# VRegion 可选值

使用 `code.byted.org/gopkg/env` 中定义的标准 VRegion 常量：

| VRegion | 说明 | StandardEnv 映射 |
|---------|------|------------------|
| `Singapore-Central` | 新加坡（默认值） | online_i18n |
| `US-East` | 美东 | online_i18n |
| `US-West` | 美西 | online_i18n |
| `China-North` | 中国北方 | online_cn |
| `China-East` | 中国华东 | online_cn |
| `EU-TTP` | 欧洲 TTP | online_euttp |
| `EU-TTP2` | 欧洲 TTP2 | online_euttp |
| `US-TTP` | 美国 TTP | online_usttp |
| `US-TTP2` | 美国 TTP2 | online_usttp |
| `US-EastRed` | 美东 Red | online_euttp |
| `China-BOE` | 中国 BOE 测试环境 | boe |
| `US-BOE` | 国际 BOE 测试环境 | boe |

> **重要**：VRegion 决定了 API 路由（通过 StandardEnv）和 JWT 鉴权类型。查询不同区域的环境时必须指定正确的 vregion。
