# Upgrade Ticket Monitoring

本文件提供一个可复用的监控脚本模板，用于轮询 `GetDeploymentTicket`，并在超时或终态时退出。

## 建议默认参数

- interval: 60s
- timeout: 600s（10min）

## Shell 模板

**重要**：`<base-dir>` 是系统提供的 Base directory for this skill，需要在实际使用时替换为真实路径。

```bash
CONFIG="<base-dir>/assets/config.json"
TICKET_ID="$1"

interval=60
timeout=600

start=$(date +%s)

while true; do
  now=$(date +%s)
  elapsed=$((now - start))
  if [[ $elapsed -ge $timeout ]]; then
    echo "[WARN] monitoring timeout after ${timeout}s"
    echo "Check in console: https://cloud-boe.bytedance.net/tce/deployment_new/${TICKET_ID}"
    exit 0
  fi

  resp=$(byte-cli --config "$CONFIG" TCE BOE GetDeploymentTicket --ticket-id "$TICKET_ID") || exit $?

  # 这里的字段名以实际返回为准；常见：.data.meta.status / .data.meta.status_display
  status=$(echo "$resp" | jq -r '.response_body.data.meta.status // empty')
  display=$(echo "$resp" | jq -r '.response_body.data.meta.status_display // empty')

  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] status=${status} (${display})"

  case "$status" in
    success|finished|failed|cancelled)
      echo "[DONE] terminal status: ${status}"
      echo "Console: https://cloud-boe.bytedance.net/tce/deployment_new/${TICKET_ID}"
      exit 0
      ;;
  esac

  sleep $interval
done
```

## 常见问题

- `No valid JWT token`: 说明 cookies/JWT 失效，先登录再监控。
- `jq: command not found`: 这段脚本依赖 `jq`；如果环境没有 `jq`，用 `--output-filter` 也可以简化提取。
