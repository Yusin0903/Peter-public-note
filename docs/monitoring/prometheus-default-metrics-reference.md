---
sidebar_position: 9
---

# Prometheus Chart 15.5.3 預設 Metrics 參考手冊

> Chart: `prometheus-community/prometheus` v15.5.3  
> 環境: AWS EKS（無自訂 scrape config）  
> 最後更新: 2026-04-22

---

## 1. 概述

`prometheus-community/prometheus` chart 15.5.3 預設採用 **annotation-based service discovery**：Prometheus 會自動掃描 Kubernetes 內所有 Service 和 Pod，只要帶有特定 annotation 就會被納入抓取。

### 預設啟用的子元件

| 子元件 | 類型 | 說明 |
|--------|------|------|
| `kube-state-metrics` | Deployment | 將 Kubernetes 物件狀態轉成 `kube_*` metrics |
| `prometheus-node-exporter` | DaemonSet | 每個節點上收集 OS 層級的 `node_*` metrics |
| `alertmanager` | Deployment | 預設啟用，可透過 Helm values 關閉 |
| `pushgateway` | Deployment | 預設啟用，可透過 Helm values 關閉 |

---

## 2. Scrape Jobs 清單

| Job 名稱 | 抓取來源 | 主要 Metrics 類別 | 備註 |
|----------|----------|-------------------|------|
| `prometheus` | Prometheus server `/metrics` | `prometheus_*` | 自我監控 |
| `kubernetes-apiservers` | kube-apiserver `/metrics`（透過 apiserver） | `apiserver_*` | 只抓 HTTPS 443 |
| `kubernetes-nodes` | kubelet `/metrics`（透過 apiserver proxy） | `kubelet_*` | 節點層級 kubelet 指標 |
| `kubernetes-nodes-cadvisor` | kubelet `/metrics/cadvisor`（透過 apiserver proxy） | `container_*` | container 層級資源用量 |
| `kubernetes-service-endpoints` | 有 `prometheus.io/scrape: "true"` 的 Service Endpoint | 應用程式自訂 metrics | annotation-based |
| `kubernetes-service-endpoints-slow` | 同上，scrape timeout 更長 | 應用程式自訂 metrics | 給 /metrics 較慢的服務 |
| `kubernetes-pods` | 有 `prometheus.io/scrape: "true"` 的 Pod | 應用程式自訂 metrics | annotation-based |
| `kubernetes-pods-slow` | 同上，scrape timeout 更長 | 應用程式自訂 metrics | 給 /metrics 較慢的 Pod |
| `kubernetes-services` | 有 `prometheus.io/probe: "true"` 的 Service | blackbox probe 結果 | HTTP probe（需 blackbox-exporter） |

---

## 3. kube-state-metrics 指標（`kube_*`）

kube-state-metrics 監聽 Kubernetes API Server，將物件的**期望狀態**（spec/status）轉成 Prometheus metrics。

### 3.1 Pod

| Metric Name | 說明 |
|-------------|------|
| `kube_pod_status_phase` | Pod 目前的 phase（Pending/Running/Succeeded/Failed/Unknown） |
| `kube_pod_status_ready` | Pod ready condition（0/1） |
| `kube_pod_container_status_running` | container 是否在 running 狀態 |
| `kube_pod_container_status_waiting` | container 是否在 waiting 狀態 |
| `kube_pod_container_status_waiting_reason` | waiting 的原因（CrashLoopBackOff、ImagePullBackOff 等） |
| `kube_pod_container_status_terminated_reason` | terminated 的原因（OOMKilled、Error 等） |
| `kube_pod_container_resource_requests` | container 的 resource request（CPU/memory） |
| `kube_pod_container_resource_limits` | container 的 resource limit（CPU/memory） |
| `kube_pod_container_status_restarts_total` | container 重啟次數累計 |
| `kube_pod_info` | Pod 的 metadata（node、namespace、ip 等） |
| `kube_pod_created` | Pod 創建時間（unix timestamp） |
| `kube_pod_owner` | Pod 的 owner reference（Deployment、DaemonSet 等） |
| `kube_pod_labels` | Pod 的所有 labels（以 label_ 前綴轉成 metrics labels） |
| `kube_pod_annotations` | Pod 的 annotation |

### 3.2 Deployment

| Metric Name | 說明 |
|-------------|------|
| `kube_deployment_status_replicas` | 目前的 replica 數量 |
| `kube_deployment_status_replicas_ready` | 目前 ready 的 replica 數量 |
| `kube_deployment_status_replicas_available` | 目前 available 的 replica 數量 |
| `kube_deployment_status_replicas_unavailable` | 目前 unavailable 的 replica 數量 |
| `kube_deployment_spec_replicas` | 期望的 replica 數量 |
| `kube_deployment_status_observed_generation` | Deployment controller 觀察到的 generation |
| `kube_deployment_metadata_generation` | spec 的 generation |
| `kube_deployment_status_condition` | Deployment condition（Available、Progressing 等） |

### 3.3 StatefulSet

| Metric Name | 說明 |
|-------------|------|
| `kube_statefulset_status_replicas` | 目前的 replica 數量 |
| `kube_statefulset_status_replicas_ready` | 目前 ready 的 replica 數量 |
| `kube_statefulset_status_replicas_current` | 目前版本的 replica 數量 |
| `kube_statefulset_spec_replicas` | 期望的 replica 數量 |
| `kube_statefulset_status_observed_generation` | 觀察到的 generation |

### 3.4 DaemonSet

| Metric Name | 說明 |
|-------------|------|
| `kube_daemonset_status_desired_number_scheduled` | 期望在多少個節點上運行 |
| `kube_daemonset_status_current_number_scheduled` | 目前已排程的數量 |
| `kube_daemonset_status_number_ready` | 目前 ready 的數量 |
| `kube_daemonset_status_number_misscheduled` | 不應排程卻被排程的數量 |
| `kube_daemonset_status_number_unavailable` | unavailable 的數量 |

### 3.5 Node

| Metric Name | 說明 |
|-------------|------|
| `kube_node_status_condition` | 節點 condition（Ready、MemoryPressure、DiskPressure、PIDPressure 等） |
| `kube_node_status_allocatable` | 節點可分配的資源量（CPU、memory、pods） |
| `kube_node_status_capacity` | 節點的總資源容量 |
| `kube_node_info` | 節點 metadata（kernel、OS、容器 runtime 版本等） |
| `kube_node_created` | 節點加入時間 |
| `kube_node_labels` | 節點的 labels |
| `kube_node_spec_taint` | 節點的 taint |
| `kube_node_spec_unschedulable` | 節點是否被設為 unschedulable |

### 3.6 PersistentVolumeClaim（PVC）

| Metric Name | 說明 |
|-------------|------|
| `kube_persistentvolumeclaim_status_phase` | PVC 的 phase（Bound/Pending/Lost） |
| `kube_persistentvolumeclaim_resource_requests_storage_bytes` | PVC 申請的 storage 大小 |
| `kube_persistentvolumeclaim_info` | PVC 的 metadata（storageClass、volumeName 等） |

### 3.7 PersistentVolume（PV）

| Metric Name | 說明 |
|-------------|------|
| `kube_persistentvolume_status_phase` | PV 的 phase（Bound/Available/Released/Failed） |
| `kube_persistentvolume_capacity_bytes` | PV 的容量 |
| `kube_persistentvolume_info` | PV 的 metadata |

### 3.8 Job / CronJob

| Metric Name | 說明 |
|-------------|------|
| `kube_job_status_succeeded` | 成功完成的 Pod 數量 |
| `kube_job_status_failed` | 失敗的 Pod 數量 |
| `kube_job_status_active` | 目前活躍的 Pod 數量 |
| `kube_job_complete` | Job 是否已完成 |
| `kube_job_failed` | Job 是否已失敗 |
| `kube_job_spec_completions` | 期望的完成次數 |
| `kube_cronjob_next_schedule_time` | 下次排程執行時間 |
| `kube_cronjob_status_last_schedule_time` | 上次排程時間 |
| `kube_cronjob_status_active` | 目前活躍的 Job 數量 |

### 3.9 HorizontalPodAutoscaler（HPA）

| Metric Name | 說明 |
|-------------|------|
| `kube_horizontalpodautoscaler_status_current_replicas` | 目前的 replica 數量 |
| `kube_horizontalpodautoscaler_status_desired_replicas` | HPA 期望的 replica 數量 |
| `kube_horizontalpodautoscaler_spec_min_replicas` | 最小 replica 數 |
| `kube_horizontalpodautoscaler_spec_max_replicas` | 最大 replica 數 |
| `kube_horizontalpodautoscaler_status_condition` | HPA condition（ScalingActive、AbleToScale、ScalingLimited 等） |

### 3.10 Namespace / ResourceQuota

| Metric Name | 說明 |
|-------------|------|
| `kube_namespace_status_phase` | Namespace 的 phase（Active/Terminating） |
| `kube_resourcequota` | ResourceQuota 的 used/hard 值 |

### 3.11 Service / Endpoint

| Metric Name | 說明 |
|-------------|------|
| `kube_service_info` | Service 的 metadata |
| `kube_service_spec_type` | Service 類型（ClusterIP、NodePort、LoadBalancer） |
| `kube_endpoint_info` | Endpoint 的基本資訊 |
| `kube_endpoint_address_available` | Endpoint 可用位址數量 |
| `kube_endpoint_address_not_ready` | Endpoint 不可用位址數量 |

---

## 4. node-exporter 指標（`node_*`）

node-exporter 以 DaemonSet 部署在每個節點上，收集 OS 層級的 metrics。

### 4.1 CPU

| Metric Name | 說明 |
|-------------|------|
| `node_cpu_seconds_total` | CPU 各模式（user/system/idle/iowait/steal 等）累計秒數，Counter |
| `node_load1` | 1 分鐘平均負載 |
| `node_load5` | 5 分鐘平均負載 |
| `node_load15` | 15 分鐘平均負載 |

### 4.2 Memory

| Metric Name | 說明 |
|-------------|------|
| `node_memory_MemTotal_bytes` | 節點總記憶體 |
| `node_memory_MemFree_bytes` | 空閒記憶體 |
| `node_memory_MemAvailable_bytes` | 可用記憶體（含 buffer/cache） |
| `node_memory_Buffers_bytes` | Buffer 記憶體 |
| `node_memory_Cached_bytes` | Cache 記憶體 |
| `node_memory_SwapTotal_bytes` | Swap 總量 |
| `node_memory_SwapFree_bytes` | 空閒 Swap |

### 4.3 Disk I/O

| Metric Name | 說明 |
|-------------|------|
| `node_disk_read_bytes_total` | 磁碟讀取累計 bytes，Counter |
| `node_disk_written_bytes_total` | 磁碟寫入累計 bytes，Counter |
| `node_disk_reads_completed_total` | 讀取完成次數，Counter |
| `node_disk_writes_completed_total` | 寫入完成次數，Counter |
| `node_disk_io_time_seconds_total` | I/O 操作累計時間，Counter |
| `node_disk_io_time_weighted_seconds_total` | 加權 I/O 時間（用來計算 utilization） |

### 4.4 Filesystem

| Metric Name | 說明 |
|-------------|------|
| `node_filesystem_size_bytes` | 檔案系統總大小 |
| `node_filesystem_free_bytes` | 檔案系統空閒空間 |
| `node_filesystem_avail_bytes` | 非 root 可用空間 |
| `node_filesystem_files` | inode 總數 |
| `node_filesystem_files_free` | 空閒 inode 數 |
| `node_filesystem_readonly` | 是否唯讀（0/1） |

### 4.5 Network

| Metric Name | 說明 |
|-------------|------|
| `node_network_receive_bytes_total` | 網路介面接收累計 bytes，Counter |
| `node_network_transmit_bytes_total` | 網路介面發送累計 bytes，Counter |
| `node_network_receive_packets_total` | 接收封包數，Counter |
| `node_network_transmit_packets_total` | 發送封包數，Counter |
| `node_network_receive_errs_total` | 接收錯誤數，Counter |
| `node_network_transmit_errs_total` | 發送錯誤數，Counter |
| `node_network_receive_drop_total` | 接收丟包數，Counter |
| `node_network_transmit_drop_total` | 發送丟包數，Counter |
| `node_network_up` | 網路介面是否 up（0/1） |

### 4.6 System

| Metric Name | 說明 |
|-------------|------|
| `node_boot_time_seconds` | 節點開機時間（unix timestamp） |
| `node_uname_info` | uname 資訊（kernel 版本、機器類型等） |
| `node_time_seconds` | 目前 unix 時間 |
| `node_os_info` | OS 資訊（名稱、版本等） |

### 4.7 Process / File Descriptor

| Metric Name | 說明 |
|-------------|------|
| `node_filefd_allocated` | 系統目前開啟的 file descriptor 數量 |
| `node_filefd_maximum` | 系統最大允許的 file descriptor 數量 |
| `node_processes_running` | 目前 running 狀態的 process 數 |
| `node_processes_blocked` | 目前 blocked 狀態的 process 數 |

---

## 5. cAdvisor 指標（`container_*`）

cAdvisor 內建於 kubelet，透過 `kubernetes-nodes-cadvisor` job 抓取。提供 container 層級的資源用量。

> 注意：`container=""` label 的資料列代表整個 Pod 的彙總；`container="POD"` 代表 pause container。

### 5.1 Memory

| Metric Name | 說明 |
|-------------|------|
| `container_memory_working_set_bytes` | Working set 記憶體（OOM killer 的依據，最常用） |
| `container_memory_usage_bytes` | 總記憶體用量（含 cache） |
| `container_memory_rss` | RSS（常駐集大小） |
| `container_memory_cache` | 頁面快取大小 |
| `container_memory_swap` | Swap 用量 |
| `container_memory_limits` | Memory limit（來自 Kubernetes limit） |
| `container_memory_requests` | Memory request（來自 Kubernetes request） |
| `container_memory_failcnt` | 記憶體分配失敗次數，Counter |
| `container_memory_failures_total` | 記憶體限制命中次數，Counter（major/minor） |

### 5.2 CPU

| Metric Name | 說明 |
|-------------|------|
| `container_cpu_usage_seconds_total` | container CPU 累計使用時間，Counter |
| `container_cpu_system_seconds_total` | kernel 模式 CPU 時間，Counter |
| `container_cpu_user_seconds_total` | user 模式 CPU 時間，Counter |
| `container_cpu_cfs_throttled_seconds_total` | CPU throttle 累計時間，Counter（偵測 CPU throttling 的關鍵） |
| `container_cpu_cfs_throttled_periods_total` | 被 throttle 的 CFS period 次數，Counter |
| `container_cpu_cfs_periods_total` | 總 CFS period 次數，Counter |

### 5.3 Network

| Metric Name | 說明 |
|-------------|------|
| `container_network_receive_bytes_total` | container 網路介面接收 bytes，Counter |
| `container_network_transmit_bytes_total` | container 網路介面發送 bytes，Counter |
| `container_network_receive_packets_total` | 接收封包數，Counter |
| `container_network_transmit_packets_total` | 發送封包數，Counter |
| `container_network_receive_errors_total` | 接收錯誤數，Counter |
| `container_network_transmit_errors_total` | 發送錯誤數，Counter |
| `container_network_receive_packets_dropped_total` | 接收丟包數，Counter |
| `container_network_transmit_packets_dropped_total` | 發送丟包數，Counter |

### 5.4 Filesystem（container 層）

| Metric Name | 說明 |
|-------------|------|
| `container_fs_usage_bytes` | container 使用的 filesystem bytes |
| `container_fs_limit_bytes` | container 的 filesystem 上限 |
| `container_fs_reads_bytes_total` | 讀取累計 bytes，Counter |
| `container_fs_writes_bytes_total` | 寫入累計 bytes，Counter |
| `container_fs_reads_total` | 讀取次數，Counter |
| `container_fs_writes_total` | 寫入次數，Counter |

### 5.5 其他

| Metric Name | 說明 |
|-------------|------|
| `container_start_time_seconds` | container 啟動時間（unix timestamp） |
| `container_last_seen` | 最後一次觀察到 container 的時間 |
| `container_oom_events_total` | container 發生 OOM 事件次數，Counter |
| `container_processes` | container 內的 process 數量 |
| `container_threads` | container 內的 thread 數量 |
| `container_threads_max` | container 的最大 thread 限制 |
| `container_spec_cpu_quota` | CPU quota（CFS） |
| `container_spec_cpu_period` | CPU period（CFS） |
| `container_spec_memory_limit_bytes` | Memory limit（cgroup 設定值） |

---

## 6. kubelet 指標（`kubelet_*`）

透過 `kubernetes-nodes` job 從 kubelet `/metrics` 抓取，反映 kubelet 自身的運作狀態。

| Metric Name | 說明 |
|-------------|------|
| `kubelet_running_pods` | 目前 running 的 Pod 數量 |
| `kubelet_running_containers` | 目前 running 的 container 數量 |
| `kubelet_pod_start_duration_seconds` | Pod 啟動時間分佈，Histogram |
| `kubelet_pod_worker_duration_seconds` | Pod worker 處理時間，Histogram |
| `kubelet_node_config_error` | 節點設定是否有錯誤（0/1） |
| `kubelet_container_log_filesystem_used_bytes` | container log 使用的 filesystem bytes |
| `kubelet_runtime_operations_total` | container runtime 操作次數，Counter（按類型） |
| `kubelet_runtime_operations_errors_total` | container runtime 操作錯誤次數，Counter |
| `kubelet_runtime_operations_duration_seconds` | container runtime 操作時間，Histogram |
| `kubelet_cgroup_manager_duration_seconds` | cgroup manager 操作時間，Histogram |
| `kubelet_pleg_relist_duration_seconds` | PLEG relist 時間，Histogram |
| `kubelet_pleg_relist_interval_seconds` | PLEG relist 間隔，Histogram |
| `kubelet_pleg_last_seen_seconds` | PLEG 最後活躍時間 |
| `kubelet_http_requests_total` | kubelet HTTP 請求數，Counter |
| `kubelet_certificate_manager_client_ttl_seconds` | 用戶端憑證的 TTL |

> EKS 特別注意：`kubelet_volume_stats_*` 系列（volume 使用量）在 EKS 上可能因為 relabeling 設定而沒有資料，詳見第 10 節。

---

## 7. Prometheus Self-Metrics（`prometheus_*`）

透過 `prometheus` job 抓取 Prometheus server 自己的 `/metrics`。

### 7.1 TSDB（時序資料庫）

| Metric Name | 說明 |
|-------------|------|
| `prometheus_tsdb_head_samples_appended_total` | 寫入 head block 的樣本數，Counter（衡量 ingestion 速率的關鍵） |
| `prometheus_tsdb_head_series` | head block 中目前的 time series 數量（cardinality） |
| `prometheus_tsdb_head_chunks` | head block 中的 chunks 數量 |
| `prometheus_tsdb_blocks_loaded` | 目前載入的 block 數量 |
| `prometheus_tsdb_compactions_total` | 執行 compaction 的次數，Counter |
| `prometheus_tsdb_compaction_duration_seconds` | compaction 耗時，Histogram |
| `prometheus_tsdb_wal_corruptions_total` | WAL 損毀次數，Counter |
| `prometheus_tsdb_wal_fsync_duration_seconds` | WAL fsync 耗時，Histogram |
| `prometheus_tsdb_storage_blocks_bytes` | 所有 blocks 佔用的 bytes |
| `prometheus_tsdb_symbol_table_size_bytes` | symbol table 大小 |
| `prometheus_tsdb_too_old_samples_total` | 太舊而被拒絕的樣本數，Counter |
| `prometheus_tsdb_out_of_order_samples_total` | 亂序而被拒絕的樣本數，Counter |

### 7.2 Remote Write

| Metric Name | 說明 |
|-------------|------|
| `prometheus_remote_storage_samples_in_total` | 進入 remote write queue 的樣本數，Counter |
| `prometheus_remote_storage_samples_pending` | 目前 queue 中待傳送的樣本數 |
| `prometheus_remote_storage_samples_sent_total` | 成功送出的樣本數，Counter |
| `prometheus_remote_storage_samples_failed_total` | 送出失敗的樣本數，Counter |
| `prometheus_remote_storage_samples_dropped_total` | 因 queue 滿而丟棄的樣本數，Counter |
| `prometheus_remote_storage_queue_highest_sent_timestamp_seconds` | queue 最後成功送出的時間戳（用來偵測 lag） |
| `prometheus_remote_storage_highest_timestamp_in_seconds` | 最新進入 queue 的時間戳 |
| `prometheus_remote_storage_shard_capacity` | 每個 shard 的容量 |
| `prometheus_remote_storage_shards` | 目前的 shard 數量 |
| `prometheus_remote_storage_max_shards` | 最大 shard 數量 |
| `prometheus_remote_storage_sent_batch_duration_seconds` | batch 發送耗時，Histogram |

### 7.3 Scrape

| Metric Name | 說明 |
|-------------|------|
| `prometheus_scrape_duration_seconds` | scrape 耗時，Summary |
| `scrape_duration_seconds` | 各 target 的 scrape 耗時 |
| `scrape_samples_scraped` | 各 target 抓到的樣本數 |
| `scrape_samples_post_metric_relabeling` | relabeling 後的樣本數 |
| `scrape_series_added` | 新增的 series 數量 |
| `up` | target 是否可被抓取（1=成功，0=失敗） |

### 7.4 其他 Prometheus 系統

| Metric Name | 說明 |
|-------------|------|
| `prometheus_config_last_reload_successful` | 最後一次 config reload 是否成功（0/1） |
| `prometheus_config_last_reload_success_timestamp_seconds` | 最後成功 reload 的時間 |
| `prometheus_rule_evaluation_duration_seconds` | alerting/recording rule 評估耗時，Histogram |
| `prometheus_rule_evaluations_total` | rule 評估次數，Counter |
| `prometheus_rule_evaluation_failures_total` | rule 評估失敗次數，Counter |
| `prometheus_notifications_sent_total` | 送出 alert 通知次數，Counter |
| `prometheus_notifications_errors_total` | alert 通知錯誤次數，Counter |
| `prometheus_http_requests_total` | Prometheus HTTP 請求數，Counter |

---

## 8. kubernetes-apiservers 指標（`apiserver_*`）

透過 `kubernetes-apiservers` job 抓取 kube-apiserver 的 `/metrics`。

| Metric Name | 說明 |
|-------------|------|
| `apiserver_request_total` | API 請求總數，Counter（按 verb、resource、code 等分） |
| `apiserver_request_duration_seconds` | API 請求處理時間，Histogram |
| `apiserver_request_filter_duration_seconds` | request filter 處理時間，Histogram |
| `apiserver_current_inflight_requests` | 目前進行中的請求數（readwriteKind） |
| `apiserver_dropped_requests_total` | 被丟棄的請求數（流量控制） |
| `apiserver_request_aborts_total` | 被中止的請求數，Counter |
| `apiserver_longrunning_requests` | 目前正在進行的長時間請求數 |
| `apiserver_registered_watchers` | 目前已註冊的 watcher 數量 |
| `apiserver_watch_events_total` | watch event 數量，Counter |
| `apiserver_watch_events_sizes` | watch event 大小，Histogram |
| `apiserver_storage_objects` | etcd 中各種物件的數量（按 resource 分） |
| `apiserver_storage_db_total_size_in_bytes` | etcd 資料庫大小（EKS 上可能不暴露） |
| `apiserver_audit_event_total` | audit event 數量，Counter |
| `etcd_request_duration_seconds` | etcd 請求耗時，Histogram |
| `etcd_db_total_size_in_bytes` | etcd 資料庫大小 |
| `process_cpu_seconds_total` | apiserver process 的 CPU 使用時間 |
| `process_resident_memory_bytes` | apiserver process 的 RSS 記憶體 |

---

## 9. Annotation-based Discovery

讓自己的 App 被 Prometheus 自動收集，需要在 Kubernetes 物件上加 annotation。

### 9.1 Service Annotation（推薦用於長期運行的服務）

```yaml
annotations:
  prometheus.io/scrape: "true"          # 必填：啟用抓取
  prometheus.io/port: "8080"            # 選填：指定 metrics port（預設用 Service port）
  prometheus.io/path: "/metrics"        # 選填：指定 metrics path（預設 /metrics）
  prometheus.io/scheme: "http"          # 選填：http 或 https（預設 http）
```

### 9.2 Pod Annotation（推薦用於 sidecar 或無對應 Service 的 Pod）

```yaml
annotations:
  prometheus.io/scrape: "true"          # 必填：啟用抓取
  prometheus.io/port: "9090"            # 選填：指定 metrics port
  prometheus.io/path: "/metrics"        # 選填：指定 metrics path
  prometheus.io/scheme: "http"          # 選填：http 或 https
```

### 9.3 Probe Annotation（HTTP probe，需 blackbox-exporter）

```yaml
annotations:
  prometheus.io/probe: "true"           # 使用 blackbox probe 而非直接抓 /metrics
```

### 9.4 注意事項

| 事項 | 說明 |
|------|------|
| annotation value 必須是字串 | `"true"` 而非 `true`（YAML 要加引號） |
| 多 Port 情況 | 若 Service 有多個 port，需明確指定 `prometheus.io/port` |
| 命名空間隔離 | 預設所有 namespace 都會被掃描（chart 預設無 namespace 限制） |
| `kubernetes-service-endpoints-slow` | scrape timeout 更長（預設 10m），適合 /metrics 回應慢的服務 |

---

## 10. 已知在 EKS 上可能沒資料的 Metrics

| Metric Name | 預期來源 | 沒資料的原因 |
|-------------|----------|-------------|
| `kubelet_volume_stats_used_bytes` | kubelet `/metrics` | EKS managed node group 上 kubelet 可能因 relabeling 設定而不暴露 volume stats |
| `kubelet_volume_stats_capacity_bytes` | kubelet `/metrics` | 同上 |
| `kubelet_volume_stats_available_bytes` | kubelet `/metrics` | 同上 |

### 讓額外的 target 被 Prometheus 抓取

若有額外的 exporter 或服務需要被 scrape 但沒有自動被發現，可以用兩種方式：

**方式 1：加 annotation 到 Service/Pod（推薦）**
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

**方式 2：在 Prometheus values.yaml 加自訂 scrape job**
```yaml
extraScrapeConfigs: |
  - job_name: 'my-custom-exporter'
    static_configs:
      - targets:
        - 'my-exporter-svc:9090'
```

---

## 附錄：快速查詢 — 常用 PromQL 範本

| 查詢目的 | PromQL |
|----------|--------|
| 容器 CPU 使用率（%） | `rate(container_cpu_usage_seconds_total{container!=""}[5m]) / on(pod, namespace) kube_pod_container_resource_limits{resource="cpu"} * 100` |
| 容器記憶體使用率（%） | `container_memory_working_set_bytes{container!=""} / on(pod, namespace) kube_pod_container_resource_limits{resource="memory"} * 100` |
| Pod 不健康（非 Running） | `kube_pod_status_phase{phase!="Running",phase!="Succeeded"}` |
| Node 可用記憶體 | `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100` |
| CPU throttle 比率 | `rate(container_cpu_cfs_throttled_periods_total[5m]) / rate(container_cpu_cfs_periods_total[5m])` |
| Remote write 延遲秒數 | `time() - prometheus_remote_storage_queue_highest_sent_timestamp_seconds` |
| 目前 series 數量（cardinality） | `prometheus_tsdb_head_series` |
| Deployment rollout 卡住 | `kube_deployment_status_replicas_unavailable > 0` |
| OOMKilled container | `kube_pod_container_status_terminated_reason{reason="OOMKilled"}` |
| CrashLoopBackOff | `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}` |
