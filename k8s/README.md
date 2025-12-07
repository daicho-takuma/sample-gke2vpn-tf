# PSC接続テスト手順

GKEクラスターにPodを立てて、PSC経由でアクセスできるか確認する手順です。

## 前提条件

1. Terraformでリソースが作成済みであること
2. PSCエンドポイントのステータスが「承認済み」になっていること
3. GKEクラスターが起動していること
4. `gcloud` と `kubectl` がインストールされていること

## 方法1: 自動テストスクリプトを使用

スクリプトはTerraformのoutputからプロジェクトID、クラスター名、ロケーションを自動取得します。
Pod名は引数で指定できます（省略時は "test-psc-pod" を使用）。

```bash
cd /Users/s25682/Desktop/sample-cloudrun2vpn-tf

# デフォルトのPod名を使用
./scripts/test-psc-connection.sh

# カスタムPod名を指定
./scripts/test-psc-connection.sh my-test-pod
```

## 方法2: 手動でテスト

### 1. TerraformのoutputからPSCエンドポイントIPを取得

```bash
cd terraform
terraform output psc_endpoint_ip
# 例: "10.0.20.2"
```

### 2. GKEクラスターに接続

```bash
gcloud container clusters get-credentials test-gke2vpn-gke-cluster \
  --location asia-northeast1 \
  --project YOUR_PROJECT_ID
```

### 3. テスト用Podを作成

```bash
cd ..
kubectl apply -f k8s/test-psc-pod.yaml
```

### 4. Podの起動を待機

```bash
kubectl wait --for=condition=Ready pod/test-psc-pod --timeout=120s
```

### 5. PodからPSCエンドポイント経由でアクセス

```bash
# PSCエンドポイントIPを取得（例: 10.0.20.2）
PSC_IP=$(cd terraform && terraform output -raw psc_endpoint_ip)

# HTTPリクエストを送信
kubectl exec test-psc-pod -- curl -v http://${PSC_IP}
```

### 6. 結果の確認

- **成功**: HTTPレスポンスが返ってくる
- **失敗**: タイムアウトまたは接続エラー

### 7. Podを削除（オプション）

```bash
kubectl delete pod test-psc-pod
```

## トラブルシューティング

### PSCエンドポイントが「承認待ち」状態の場合

1. GCPコンソールでService Attachmentを確認
2. `connection_preference` が `ACCEPT_AUTOMATIC` になっているか確認
3. 必要に応じて `terraform apply` を実行

### 接続がタイムアウトする場合

1. **PSCエンドポイントのステータス確認**
   ```bash
   gcloud compute forwarding-rules describe test-gke2vpn-psc-endpoint \
     --region asia-northeast1 \
     --project YOUR_PROJECT_ID
   ```

2. **ILBのバックエンド確認**
   - AWS EC2インスタンスが起動しているか
   - NEGにエンドポイントが登録されているか

3. **ファイアウォールルール確認**
   - Consumer VPCからProducer VPCへの通信が許可されているか
   - ILBのヘルスチェックが通るか

### Podが起動しない場合

1. GKEクラスターの状態を確認
   ```bash
   gcloud container clusters describe test-gke2vpn-gke-cluster \
     --location asia-northeast1 \
     --project YOUR_PROJECT_ID
   ```

2. Podのログを確認
   ```bash
   kubectl describe pod test-psc-pod
   kubectl logs test-psc-pod
   ```
