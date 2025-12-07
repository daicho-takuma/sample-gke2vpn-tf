#!/bin/bash

# PSC接続テストスクリプト
# このスクリプトはGKEクラスターにPodを作成し、PSCエンドポイント経由でアクセスをテストします
#
# 使用方法:
#   ./scripts/test-psc-connection.sh [POD_NAME]
#
# 引数:
#   POD_NAME: テスト用Pod名（省略可。省略時は "test-psc-pod" を使用）
#
# 注意: プロジェクトID、クラスター名、ロケーションはTerraformのoutputから自動取得します
#
# 例:
#   ./scripts/test-psc-connection.sh
#   ./scripts/test-psc-connection.sh my-test-pod

set -e

# Terraformのoutputから値を取得
echo "Terraformのoutputから設定値を取得中..."
cd terraform

# プロジェクトIDの取得（常にTerraformから取得）
if ! PROJECT_ID=$(terraform output -raw project_id 2>/dev/null); then
  echo "エラー: TerraformのoutputからプロジェクトIDを取得できませんでした"
  echo "Terraformのapplyが実行されているか確認してください"
  exit 1
fi

# Pod名の取得（第1引数が指定されている場合）
if [ $# -ge 1 ] && [ -n "$1" ]; then
  POD_NAME="$1"
else
  POD_NAME="test-psc-pod"
fi

# クラスター名とロケーションを取得
if ! CLUSTER_NAME=$(terraform output -raw gke_cluster_name 2>/dev/null); then
  echo "エラー: TerraformのoutputからGKEクラスター名を取得できませんでした"
  exit 1
fi

if ! LOCATION=$(terraform output -raw gke_cluster_location 2>/dev/null); then
  echo "エラー: TerraformのoutputからGKEクラスターのロケーションを取得できませんでした"
  exit 1
fi

# PSCエンドポイントIPを取得
if ! PSC_ENDPOINT_IP=$(terraform output -raw psc_endpoint_ip 2>/dev/null); then
  echo "エラー: TerraformのoutputからPSCエンドポイントIPを取得できませんでした"
  exit 1
fi

cd ..

echo "取得した設定値:"
echo "  プロジェクトID: ${PROJECT_ID}"
echo "  クラスター名: ${CLUSTER_NAME}"
echo "  ロケーション: ${LOCATION}"
echo "  Pod名: ${POD_NAME}"
echo "  PSC Endpoint IP: ${PSC_ENDPOINT_IP}"
echo ""

echo "=========================================="
echo "PSC接続テスト"
echo "=========================================="

# GKEクラスターに接続
echo ""
echo "GKEクラスターに接続中..."
gcloud container clusters get-credentials ${CLUSTER_NAME} \
  --location ${LOCATION} \
  --project ${PROJECT_ID}

# Podが既に存在する場合は削除
echo ""
echo "既存のPodを確認中..."
if kubectl get pod ${POD_NAME} &>/dev/null; then
  echo "既存のPodを削除中..."
  kubectl delete pod ${POD_NAME} --ignore-not-found=true
  sleep 5
fi

# テスト用Podを作成（マニフェストをスクリプト内に組み込み）
echo ""
echo "テスト用Podを作成中..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  labels:
    app: test-psc
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 3600; done"]
  restartPolicy: Never
EOF

# Podが起動するまで待機
echo ""
echo "Podの起動を待機中..."
kubectl wait --for=condition=Ready pod/${POD_NAME} --timeout=120s

# PodからPSCエンドポイント経由でアクセステスト
echo ""
echo "=========================================="
echo "PSCエンドポイント経由でアクセステスト"
echo "=========================================="
echo "PSC Endpoint IP: ${PSC_ENDPOINT_IP}"
echo ""

# HTTPリクエストを送信
echo "HTTPリクエストを送信中..."
TEST_RESULT=0
kubectl exec ${POD_NAME} -- curl -v -m 10 http://${PSC_ENDPOINT_IP} || TEST_RESULT=$?

echo ""
echo "=========================================="
echo "接続テスト結果"
echo "=========================================="

# Podを削除（成功・失敗に関わらず）
echo ""
echo "テスト用Podを削除中..."
kubectl delete pod ${POD_NAME} --ignore-not-found=true
echo "Podを削除しました"

# テスト結果を表示
if [ $TEST_RESULT -eq 0 ]; then
  echo "✅ 接続に成功しました！"
  exit 0
else
  echo "❌ 接続に失敗しました"
  echo ""
  echo "確認事項:"
  echo "1. PSCエンドポイントのステータスが '承認済み' になっているか確認"
  echo "2. ILBのバックエンド（AWS EC2インスタンス）が起動しているか確認"
  echo "3. ファイアウォールルールが正しく設定されているか確認"
  exit 1
fi
