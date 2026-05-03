---
sidebar_position: 16
---

# Alerting HA 設計：vmalert + Alertmanager

> 單一 vmalert pod 是 alerting 的單點故障。這份筆記記錄如何設計 HA alerting，以及 Alertmanager inhibit_rules 在多 Region 環境下的重要性。

---

## 問題：單一 vmalert = 單點故障

```
vmalert pod 重啟或 OOM 期間：
  - 沒有任何 alert rule 在執行
  - 即使線上有 pod 掛掉、error rate 飆高
  - Alertmanager 收不到任何 firing alert
  - On-call 工程師完全不知道
```

這和「Grafana 沒資料」不同。Grafana 沒資料工程師看得到，vmalert 掛掉是靜默的。

---

## vmalert HA 設計

### 方法：兩個 vmalert 同時跑，Alertmanager dedup

```
vmalert-0 ──評估相同 rules──▶ Alertmanager
vmalert-1 ──評估相同 rules──▶ Alertmanager
                                    │
                          Alertmanager 去重
                          （同一個 alert 只通知一次）
                                    │
                              Slack / PagerDuty
```

兩個 vmalert 同時評估完全一樣的 rules，產生一樣的 alert。Alertmanager 用 `group_by` 和 `dedup` 確保只發一次通知。

### vmalert Helm 設定

```yaml
# vmalert deployment
replicas: 2

# 關鍵：每個 replica 要有不同的 replica label
# 讓 Alertmanager 可以識別「這兩個 alert 是同一個，只是來自不同 vmalert」
env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name

args:
  - -rule=/config/alert-rules.yaml
  - -datasource.url=http://vmselect-vmcluster-central.monitoring.svc:8481/select/0/prometheus
  - -notifier.url=http://alertmanager.monitoring.svc:9093
  - -evaluationInterval=1m
  # 加上 replica label，讓 Alertmanager 能 dedup
  - -external.label=replica=$(POD_NAME)
```

### Alertmanager dedup 設定

```yaml
# alertmanager.yml
route:
  group_by: ['alertname', 'region', 'namespace']   # 不包含 replica
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'slack-oncall'

# Alertmanager 自動對同一個 alertname + labels（不含 replica）的告警去重
# 兩個 vmalert 發來同一個 alert → 只通知一次
```

---

## Alertmanager HA

Alertmanager 本身也支援 HA，透過 gossip 協定在多個節點間同步 silence 和通知狀態：

```yaml
# alertmanager deployment
replicas: 3

args:
  - --cluster.peer=alertmanager-0.alertmanager.monitoring.svc:9094
  - --cluster.peer=alertmanager-1.alertmanager.monitoring.svc:9094
  - --cluster.peer=alertmanager-2.alertmanager.monitoring.svc:9094
```

```
vmalert ──▶  alertmanager-0 ──gossip──▶ alertmanager-1
                                    └──▶ alertmanager-2

三個節點同步 silence 狀態：
  在 alertmanager-0 設定的 silence 會同步到 -1 和 -2
  任一節點掛掉，剩下兩個繼續正常工作
```

---

## inhibit_rules：多 Region 環境的關鍵

### 問題：一個事件觸發幾十個告警

```
某 Region vmstorage-0 磁碟滿 → 寫入失敗 → 觸發：
  ❌ VMStorageDiskHigh (warning)
  ❌ VMInsertWriteErrors (warning)
  ❌ HighErrorRate service-a (warning)
  ❌ HighErrorRate service-b (warning)
  ❌ HighErrorRate service-c (warning)
  ❌ PodRestarts service-a (warning)
  ... （可能 10+ 個 alert 全部同時 fire）

On-call 工程師的 PagerDuty 在凌晨 3 點收到 15 則通知
```

### 解法：inhibit_rules

```yaml
# alertmanager.yml
inhibit_rules:
  # 規則：如果 critical 在 fire，suppress 同 region 的所有 warning
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: ['region']   # 只 suppress 同一個 region 的

  # 規則：如果 vmstorage 掛了，suppress 所有 VM 相關的 downstream alert
  - source_matchers:
      - alertname="VMStorageNodeDown"
    target_matchers:
      - alertname=~"VMInsertWriteErrors|HighErrorRate.*"
    equal: ['region']
```

### 多 Region inhibit 範例

```yaml
inhibit_rules:
  # 一個 region 的 critical 不會 suppress 另一個 region 的 warning
  # （equal: ['region'] 確保只 suppress 同 region）
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: ['region', 'namespace']

  # vmstorage 掛了 → 同 region 的 app error rate 都 suppress
  - source_matchers:
      - alertname="VMStorageNodeDown"
    target_matchers:
      - alertname=~"High.*Rate|PodRestart.*"
    equal: ['region']

  # 整個 monitoring namespace 有問題 → suppress 所有 monitoring 的 downstream
  - source_matchers:
      - namespace="monitoring"
      - severity="critical"
    target_matchers:
      - namespace="monitoring"
      - severity="warning"
    equal: ['cluster']
```

---

## vmalert 監控自己

```promql
# vmalert 是否在正常評估 rules（這個數字應該等於 rule 數量）
vmalert_alerts_total

# 評估失敗的 rule（> 0 = rule 有語法問題或 vmselect 連不到）
rate(vmalert_iteration_missed_total[5m])

# 每次 evaluation 花多久（> 5s 表示 vmselect 有壓力）
histogram_quantile(0.99, rate(vmalert_iteration_duration_seconds_bucket[5m]))
```

**vmalert 的 watchdog alert（確保 alerting pipeline 正常）：**

```yaml
# 這個 alert 永遠在 fire，用來確認整個 pipeline 通暢
- alert: Watchdog
  expr: vector(1)
  labels:
    severity: none
  annotations:
    summary: "Alerting pipeline is working"
    description: "If you don't receive this alert every hour, alerting is broken"
```

在 Alertmanager 設定一個接收 Watchdog 的 receiver，如果一小時沒收到就知道 pipeline 斷了。

---

## 告警的 runbook 規範

每個 alert 都應該有 `runbook_url`，指向說明「怎麼處理」的文件：

```yaml
- alert: VMStorageDiskHigh
  expr: ...
  annotations:
    summary: "vmstorage 磁碟使用超過 85%"
    runbook_url: "https://github.com/org/repo/blob/main/docs/runbooks/vm-storage-disk-high.md"
    description: |
      vmstorage {{ $labels.instance }} 磁碟使用率 {{ $value | humanizePercentage }}
      預估 {{ with query "predict_linear(vm_data_size_bytes[24h], 86400)" }}
        {{ . | first | value | humanizeDuration }}
      {{ end }} 後磁碟滿
```

**Runbook 範本（vm-storage-disk-high.md）：**
```markdown
## 症狀
vmstorage 磁碟使用率超過 85%

## 立即處置
1. 確認哪個 vmstorage pod：`kubectl top pods -n monitoring`
2. 查看磁碟用量：`kubectl exec -n monitoring vmstorage-0 -- df -h /vm-data`
3. 臨時緊急降基數：調低 retentionPeriod 或啟用 stream aggregation

## 根本原因
- 高基數服務造成基數爆炸（詳見 cardinality explorer 排查）
- 新增了高基數 metric（用 VMUI cardinality explorer 確認）

## 長期解法
- 在 vminsert 啟用 stream aggregation 過濾高基數 label
- 擴充 vmstorage PVC（gp3 支援線上擴充）
```
