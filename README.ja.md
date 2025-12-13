# GCP GKE から AWS VPN への Private Service Connect 経由接続

このプロジェクトは、GCPのPrivate Service Connect (PSC) と Internal Load Balancer (ILB) を使用して、VPN接続経由でGCPのGKEクラスターをAmazon EC2インスタンスに接続する方法を実演します。

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────┐
│                        GCP (Consumer)                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Consumer VPC                                        │   │
│  │  ┌──────────────┐  ┌──────────────────────────────┐ │   │
│  │  │ GKE Cluster  │  │  PSC Endpoint                │ │   │
│  │  │              │  │  (10.0.20.2)                 │ │   │
│  │  └──────────────┘  └──────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ PSC Connection
                            │
┌─────────────────────────────────────────────────────────────┐
│                        GCP (Producer)                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Producer VPC                                        │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  Internal Load Balancer (ILB)                  │ │   │
│  │  │  └─> Service Attachment                        │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  VPN Gateway                                    │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ VPN Connection
                            │
┌─────────────────────────────────────────────────────────────┐
│                            AWS                                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  VPC (10.0.0.0/16)                                    │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  VPN Gateway                                    │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  EC2 Instance (Private Subnet)                  │ │   │
│  │  │  IP: 10.0.20.10                                │ │   │
│  │  │  HTTP Server                                   │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## コンポーネント

### GCPリソース

- **Consumer VPC**: GKEクラスターとPSCエンドポイントをホスト
- **Producer VPC**: ILB、Service Attachment、VPNゲートウェイをホスト
- **GKE Cluster**: PSC接続性をテストするためのKubernetesクラスター
- **PSC Endpoint**: Consumer VPC内のPrivate Service Connectエンドポイント
- **Internal Load Balancer (ILB)**: Producer VPC内のリージョナル内部ロードバランサー
- **Service Attachment**: ILBをPSC経由で公開
- **VPN Gateway**: GCP Producer VPCをAWS VPCに接続

### AWSリソース

- **VPC**: パブリックサブネットとプライベートサブネットを持つ仮想プライベートクラウド
- **EC2 Instance**: HTTPサーバーを実行するプライベートインスタンス
- **VPN Gateway**: AWS VPCをGCP Producer VPCに接続

## 前提条件

### 必要なツール

- Terraform >= 1.14.0
- 適切な認証情報で設定されたAWS CLI
- 適切な認証情報で設定されたGCP CLI (`gcloud`)
- kubectl がインストールされていること

### 必要なアカウントと権限

- 以下のAPIが有効になっている**GCP Project ID**:
  - Compute Engine API
  - Kubernetes Engine API
  - Cloud Resource Manager API

- 以下のリソースを作成する権限を持つ**AWSアカウント**:
  - VPC、サブネット、インターネットゲートウェイ、NATゲートウェイ
  - EC2インスタンス、セキュリティグループ、ルートテーブル
  - VPNゲートウェイ、カスタマーゲートウェイ、VPN接続
  - IAMロールとインスタンスプロファイル

### GCP APIの有効化

Terraformを実行する前に、必要なGCP APIを有効にしてください:

```bash
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

## セットアップ

### 1. Terraform変数の設定

サンプル変数ファイルをコピーして、プロジェクトIDを設定します:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`を編集して、GCPプロジェクトIDを設定します:

```hcl
project_id = "your-gcp-project-id"
```

**オプション**: `terraform.tfvars`でデフォルト値を上書きすることもできます:

```hcl
project_id = "your-gcp-project-id"
environment  = "test"        # オプション: デフォルトは "test"
project_name = "gke2vpn"     # オプション: デフォルトは "gke2vpn"
aws_region   = "ap-northeast-1"  # オプション: デフォルトは "ap-northeast-1"
gcp_region   = "asia-northeast1" # オプション: デフォルトは "asia-northeast1"
```

**注意**: `terraform.tfvars`は既に`.gitignore`に含まれており、コミットされません。

### 2. Terraformの初期化

```bash
cd terraform
terraform init
```

### 3. プランの確認

```bash
terraform plan
```

### 4. 設定の適用

```bash
terraform apply
```

これにより、以下のリソースが作成されます:

**AWSリソース:**
- パブリックサブネットとプライベートサブネットを持つVPC
- プライベートサブネット内のAmazon EC2インスタンス（t2.small、ポート80でHTTPサーバーを実行）
- VPNゲートウェイとカスタマーゲートウェイ
- ルートテーブルとセキュリティグループ
- EC2用のIAMロールとインスタンスプロファイル
- SSH鍵ペア（自動生成）

**GCPリソース:**
- Consumer VPC（GKEクラスターとPSCエンドポイントをホスト）
- Producer VPC（ILB、Service Attachment、VPNゲートウェイをホスト）
- 自動スケーリングノードプール付きGKEクラスター
- Internal Load Balancer (ILB)
- Service AttachmentとPSC Endpoint
- VPNゲートウェイとExternal VPNゲートウェイ

**注意**: 
- リソース作成には通常15-30分かかります
- VPN接続の確立には、リソース作成後にさらに10-20分かかる場合があります
- セットアップの合計時間: 約25-50分

### 5. PSCエンドポイントのステータス確認

PSCエンドポイントのステータスが「Accepted」になるまで待機します:

```bash
cd terraform
PROJECT_ID=$(terraform output -raw project_id)
PSC_ENDPOINT_NAME=$(terraform output -raw psc_service_attachment_name | sed 's/.*\///')
REGION=$(terraform output -raw gke_cluster_location)

gcloud compute forwarding-rules describe ${PSC_ENDPOINT_NAME} \
  --region ${REGION} \
  --project ${PROJECT_ID}
```

## PSC接続性のテスト

### クイックテスト

自動テストスクリプトを実行します:

```bash
./scripts/test-psc-connection.sh
```

または、カスタムPod名を指定します:

```bash
./scripts/test-psc-connection.sh my-test-pod
```

このスクリプトは以下を実行します:
1. Terraform出力から設定を取得（プロジェクトID、クラスター名、ロケーション、PSCエンドポイントIP）
2. `gcloud container clusters get-credentials`を使用してGKEクラスターに接続
3. curlコンテナでテストPodを作成
4. PSCエンドポイント経由でAmazon EC2インスタンスへのHTTP接続性をテスト
5. 詳細な接続情報を表示:
   - **接続情報**: 送信元Pod IP、送信先PSCエンドポイントIP、ターゲットAmazon EC2インスタンス
   - **レスポンス詳細**: HTTPステータスコード、レスポンス時間、レスポンスボディ
   - **接続経路**: GKE PodからAmazon EC2インスタンスへの接続経路の視覚的表現
6. テストPodを自動的にクリーンアップ

### 期待される出力

接続が成功すると、以下のような出力が表示されます:

```
==========================================
Connection Test Result
==========================================

📋 Connection Information:
  Source: GKE Pod (IP: 10.0.100.23)
  Destination: PSC Endpoint (IP: 10.0.20.2)
  Target: Amazon EC2 Instance (via VPN)

✅ Connection Status: SUCCESS

📊 Response Details:
  HTTP Status Code: 200
  Response Time: 0.123s

📝 Response Body:
  ┌─────────────────────────────────────────────────────────┐
  │ Hello World from test-gke2vpn-aws-private-vm-01         │
  └─────────────────────────────────────────────────────────┘

🔗 Connection Path:
  GKE Pod (10.0.100.23)
    ↓
  PSC Endpoint (10.0.20.2)
    ↓
  Service Attachment
    ↓
  Internal Load Balancer (Producer VPC)
    ↓
  VPN Gateway (GCP → AWS)
    ↓
  Amazon EC2 Instance ✅
```

このスクリプトは、接続ステータスについて明確な視覚的フィードバックを提供し、接続性の問題のトラブルシューティングに役立ちます。

## プロジェクト構造

```
.
├── terraform/                    # Terraform設定ファイル
│   ├── aws_*.tf                 # AWSリソース (VPC, EC2, VPN)
│   ├── gcp_*.tf                 # GCPリソース (VPC, GKE, ILB, PSC, VPN)
│   ├── locals.tf                # ローカル変数と設定
│   ├── variables.tf             # 入力変数
│   ├── outputs.tf               # 出力値
│   ├── provider.tf              # プロバイダー設定
│   ├── terraform.tf             # Terraform設定
│   └── terraform.tfvars.example # サンプル変数ファイル
├── scripts/                      # ユーティリティスクリプト
│   └── test-psc-connection.sh   # 詳細な出力付きPSC接続性テストスクリプト
├── misc/                         # その他のファイル
│   └── *.key.pub                # EC2 SSH公開鍵 (Terraformによって生成)
└── README.md                     # このファイル
```

**注意**: 以下のファイルはGitによって無視されます（`.gitignore`経由）:
- `terraform/terraform.tfvars` - 機密設定を含む（プロジェクトIDなど）
- `terraform/terraform.tfstate*` - Terraform状態ファイル
- `misc/*.key` - プライベートSSH鍵

## 設定

### デフォルト設定

以下のデフォルト値は`terraform/locals.tf`で設定されています:

- **Environment**: `test`
- **Project Name**: `gke2vpn`
- **AWS Region**: `ap-northeast-1`
- **GCP Region**: `asia-northeast1`
- **Amazon EC2 Instance Type**: `t2.small`
- **GKE Machine Type**: `e2-medium`
- **GKE Node Count**: 1-3ノード（自動スケーリング）
- **AWS VPC CIDR**: `10.0.0.0/16`
- **AWS Public Subnet**: `10.0.10.0/24`
- **AWS Private Subnet**: `10.0.20.0/24`
- **GKE Pod IP Range**: `10.0.100.0/24`
- **GKE Service IP Range**: `10.0.200.0/24`

**注意**: GCP Consumer VPCは、VPNルーティング動作をテストするために、意図的にAWS VPCと重複するCIDR範囲を使用しています。これはテスト目的で意図的なものです。

これらの設定を変更するには、`terraform apply`を実行する前に`terraform/locals.tf`を編集してください。

## 出力

Terraformを適用した後、以下の出力を取得できます:

```bash
cd terraform
terraform output
```

利用可能な出力:
- `project_id`: GCPプロジェクトID
- `gke_cluster_name`: GKEクラスター名
- `gke_cluster_location`: GKEクラスターのロケーション
- `psc_endpoint_ip`: PSCエンドポイントIPアドレス
- `psc_service_attachment_name`: サービスアタッチメント名

## トラブルシューティング

### VPN接続の問題

1. AWSとGCPの両方のコンソールでVPNトンネルのステータスを確認
2. ルートテーブルとセキュリティグループを確認
3. BGPセッションが確立されていることを確認

### PSC接続の問題

1. PSCエンドポイントのステータスが「Accepted」であることを確認
2. ILBバックエンドのヘルスを確認
3. ファイアウォールルールがトラフィックを許可していることを確認
4. GCPとAWS間のVPN接続が確立されていることを確認
5. テストスクリプトが詳細なエラー情報を表示することを確認:
   - HTTPステータスコードが200でない場合、ILBバックエンドとEC2インスタンスを確認
   - curlコマンドが失敗する場合、ネットワーク接続性とファイアウォールルールを確認

### GKEクラスターの問題

1. クラスターが実行中であることを確認: `gcloud container clusters list`
2. ノードプールのステータスを確認
3. GCPコンソールでクラスターログを確認

## クリーンアップ

すべてのリソースを削除するには:

```bash
cd terraform
terraform destroy
```

**警告**: これにより、Terraformによって作成されたすべてのリソースが削除されます:
- AWS VPC、サブネット、EC2インスタンス、VPNゲートウェイ、および関連リソース
- GCP VPC、GKEクラスター、ロードバランサー、VPNゲートウェイ、および関連リソース

**注意**: 
- リソースを削除する前に、重要なデータのバックアップがあることを確認してください
- クリーンアッププロセスには10-15分かかる場合があります
- 一部のリソース（VPN接続など）は完全に終了するまで時間がかかる場合があります

## コスト考慮事項

このプロジェクトは、AWSとGCPの両方でコストが発生するリソースを作成します:

**AWSコスト:**
- EC2インスタンス（t2.small）: 約$0.02-0.03/時間
- VPNゲートウェイ: 約$0.05/時間
- データ転送: 使用量によって異なる
- NATゲートウェイ（使用する場合）: 約$0.045/時間 + データ転送

**GCPコスト:**
- GKEクラスター: 約$0.10/時間（e2-mediumノード）
- VPNゲートウェイ: 約$0.05/時間
- ロードバランサー: 約$0.025/時間
- データ転送: 使用量によって異なる

**月額コスト見積もり**: 継続的に実行した場合、約$50-100/月。

**推奨事項**: 不要なコストを避けるため、使用していない場合はリソースを削除してください。

## セキュリティ考慮事項

- すべての機密値は`terraform.tfvars`に含める必要があります（既に`.gitignore`に含まれています）
- VPN接続は暗号化されたトンネルを使用します
- PSCはインターネットにサービスを公開せずにプライベート接続を提供します
- Amazon EC2インスタンスはプライベートサブネット内にあります（パブリックIPなし）
- EC2インスタンス用のSSH鍵はTerraformによって自動生成されます
  - プライベート鍵は`misc/`ディレクトリに保存されます（Gitによって無視されます）
  - 公開鍵は`misc/`ディレクトリに保存され、AWSにアップロードされます
- 必要に応じてセキュリティグループとファイアウォールルールを確認および調整してください
- AWSとGCPの両方で適切なIAM権限が設定されていることを確認してください

## ライセンス

これは実演目的のサンプルプロジェクトです。

## 貢献

貢献を歓迎します！コードとドキュメントが既存のスタイルに従い、適切なテストを含んでいることを確認してください。

