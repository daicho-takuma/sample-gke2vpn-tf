#########################
# Cloud VPN
# 段階的にリソースを作成中
#########################

# ----------------------
# Cloud VPN Gateway
# ステップ3: GCP側のVPN GatewayとRouterを作成
# ----------------------
resource "google_compute_ha_vpn_gateway" "vpn_gw" {
  region  = local.gcp_producer_network_config.region
  name    = "${local.env}-${local.project}-ha-vpn-gw"
  network = google_compute_network.producer_vpc.id
}

# ----------------------
# Cloud Router
# ----------------------
resource "google_compute_router" "vpn_router" {
  name    = "${local.env}-${local.project}-ha-vpn-router"
  region  = local.gcp_producer_network_config.region
  network = google_compute_network.producer_vpc.name
  bgp {
    asn = local.gcp_vpn_config.asn
  }
}

# ----------------------
# Peer VPN Gateway
# ステップ6: GCP側のExternal VPN Gatewayを作成（AWS側のVPN接続の情報を参照）
# ----------------------
resource "google_compute_external_vpn_gateway" "external_vpn_gw" {
  name            = "${local.env}-${local.project}-external-vpn-gw"
  redundancy_type = "FOUR_IPS_REDUNDANCY"
  description     = "An externally managed VPN gateway"
  interface {
    id         = 0
    ip_address = aws_vpn_connection.vpn_connection_01.tunnel1_address
  }
  interface {
    id         = 1
    ip_address = aws_vpn_connection.vpn_connection_01.tunnel2_address
  }
  interface {
    id         = 2
    ip_address = aws_vpn_connection.vpn_connection_02.tunnel1_address
  }
  interface {
    id         = 3
    ip_address = aws_vpn_connection.vpn_connection_02.tunnel2_address
  }

  depends_on = [
    aws_vpn_connection.vpn_connection_01,
    aws_vpn_connection.vpn_connection_02
  ]
}

# ----------------------
# VPN Tunnel
# ステップ7: GCP側のVPN Tunnel、Router Interface、Router Peerを段階的に作成
# ----------------------

# VPN Tunnel 1
# ステップ7-1: tunnel1とその関連リソースを作成
resource "google_compute_vpn_tunnel" "tunnel1" {
  name                            = "${local.env}-${local.project}-vpn-tunnel1"
  region                          = local.gcp_producer_network_config.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.vpn_gw.id
  peer_external_gateway           = google_compute_external_vpn_gateway.external_vpn_gw.id
  peer_external_gateway_interface = 0
  shared_secret                   = aws_vpn_connection.vpn_connection_01.tunnel1_preshared_key
  router                          = google_compute_router.vpn_router.id
  vpn_gateway_interface           = 0
  ike_version                     = 2
}

// Cloud Routerインターフェースの設定
resource "google_compute_router_interface" "tunnel1_interface" {
  name       = "${google_compute_vpn_tunnel.tunnel1.name}-interface"
  router     = google_compute_router.vpn_router.name
  ip_range   = "${aws_vpn_connection.vpn_connection_01.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel1.name
}

// BGPピアリング用のBGP情報の設定
resource "google_compute_router_peer" "tunnel1_bgp" {
  name            = "${google_compute_vpn_tunnel.tunnel1.name}-bgp"
  router          = google_compute_router.vpn_router.name
  peer_ip_address = aws_vpn_connection.vpn_connection_01.tunnel1_vgw_inside_address
  peer_asn        = aws_vpn_connection.vpn_connection_01.tunnel1_bgp_asn
  interface       = google_compute_router_interface.tunnel1_interface.name
}

# VPN Tunnel 2
# ステップ7-2: tunnel2とその関連リソースを作成
resource "google_compute_vpn_tunnel" "tunnel2" {
  name                            = "${local.env}-${local.project}-vpn-tunnel2"
  region                          = local.gcp_producer_network_config.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.vpn_gw.id
  peer_external_gateway           = google_compute_external_vpn_gateway.external_vpn_gw.id
  peer_external_gateway_interface = 1
  shared_secret                   = aws_vpn_connection.vpn_connection_01.tunnel2_preshared_key
  router                          = google_compute_router.vpn_router.id
  vpn_gateway_interface           = 0
  ike_version                     = 2
}

// Cloud Routerインターフェースの設定
resource "google_compute_router_interface" "tunnel2_interface" {
  name       = "${google_compute_vpn_tunnel.tunnel2.name}-interface"
  router     = google_compute_router.vpn_router.name
  ip_range   = "${aws_vpn_connection.vpn_connection_01.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel2.name
}

// BGPピアリング用のBGP情報の設定
resource "google_compute_router_peer" "tunnel2_bgp" {
  name            = "${google_compute_vpn_tunnel.tunnel2.name}-bgp"
  router          = google_compute_router.vpn_router.name
  peer_ip_address = aws_vpn_connection.vpn_connection_01.tunnel2_vgw_inside_address
  peer_asn        = aws_vpn_connection.vpn_connection_01.tunnel2_bgp_asn
  interface       = google_compute_router_interface.tunnel2_interface.name
}

# VPN Tunnel 3
# ステップ7-3: tunnel3とその関連リソースを作成
resource "google_compute_vpn_tunnel" "tunnel3" {
  name                            = "${local.env}-${local.project}-vpn-tunnel3"
  region                          = local.gcp_producer_network_config.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.vpn_gw.id
  peer_external_gateway           = google_compute_external_vpn_gateway.external_vpn_gw.id
  peer_external_gateway_interface = 2
  shared_secret                   = aws_vpn_connection.vpn_connection_02.tunnel1_preshared_key
  router                          = google_compute_router.vpn_router.id
  vpn_gateway_interface           = 1
  ike_version                     = 2
}

// Cloud Routerインターフェースの設定
resource "google_compute_router_interface" "tunnel3_interface" {
  name       = "${google_compute_vpn_tunnel.tunnel3.name}-interface"
  router     = google_compute_router.vpn_router.name
  ip_range   = "${aws_vpn_connection.vpn_connection_02.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel3.name
}

// BGPピアリング用のBGP情報の設定
resource "google_compute_router_peer" "tunnel3_bgp" {
  name            = "${google_compute_vpn_tunnel.tunnel3.name}-bgp"
  router          = google_compute_router.vpn_router.name
  peer_ip_address = aws_vpn_connection.vpn_connection_02.tunnel1_vgw_inside_address
  peer_asn        = aws_vpn_connection.vpn_connection_02.tunnel1_bgp_asn
  interface       = google_compute_router_interface.tunnel3_interface.name
}

# VPN Tunnel 4
# ステップ7-4: tunnel4とその関連リソースを作成
resource "google_compute_vpn_tunnel" "tunnel4" {
  name                            = "${local.env}-${local.project}-vpn-tunnel4"
  region                          = local.gcp_producer_network_config.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.vpn_gw.id
  peer_external_gateway           = google_compute_external_vpn_gateway.external_vpn_gw.id
  peer_external_gateway_interface = 3
  shared_secret                   = aws_vpn_connection.vpn_connection_02.tunnel2_preshared_key
  router                          = google_compute_router.vpn_router.id
  vpn_gateway_interface           = 1
  ike_version                     = 2
}

// Cloud Routerインターフェースの設定
resource "google_compute_router_interface" "tunnel4_interface" {
  name       = "${google_compute_vpn_tunnel.tunnel4.name}-interface"
  router     = google_compute_router.vpn_router.name
  ip_range   = "${aws_vpn_connection.vpn_connection_02.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel4.name
}

// BGPピアリング用のBGP情報の設定
resource "google_compute_router_peer" "tunnel4_bgp" {
  name            = "${google_compute_vpn_tunnel.tunnel4.name}-bgp"
  router          = google_compute_router.vpn_router.name
  peer_ip_address = aws_vpn_connection.vpn_connection_02.tunnel2_vgw_inside_address
  peer_asn        = aws_vpn_connection.vpn_connection_02.tunnel2_bgp_asn
  interface       = google_compute_router_interface.tunnel4_interface.name
}
