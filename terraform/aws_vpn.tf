#########################
# Site-to-site VPN
# 段階的にリソースを作成中
#########################

# ----------------------
# Virtual Private Gateway
# ステップ2: AWS側のVPN Gatewayを作成
# ----------------------
resource "aws_vpn_gateway" "vgw" {
  amazon_side_asn = local.aws_vpn_config.asn
  tags = {
    Name = "${local.env}-${local.project}-vgw"
  }
}

# VPN Gateway Attachment (explicit attachment)
resource "aws_vpn_gateway_attachment" "vgw_attachment" {
  vpc_id         = aws_vpc.vpc.id
  vpn_gateway_id = aws_vpn_gateway.vgw.id
}

# Propagation of route table
resource "aws_vpn_gateway_route_propagation" "vgw_propagate_public" {
  vpn_gateway_id = aws_vpn_gateway.vgw.id
  route_table_id = aws_route_table.public.id

  depends_on = [aws_vpn_gateway_attachment.vgw_attachment]
}

resource "aws_vpn_gateway_route_propagation" "vgw_propagate_private" {
  vpn_gateway_id = aws_vpn_gateway.vgw.id
  route_table_id = aws_route_table.private.id

  depends_on = [aws_vpn_gateway_attachment.vgw_attachment]
}

# ----------------------
# Customer Gateway
# ステップ4: AWS側のCustomer Gatewayを作成（GCP側のVPN GatewayのIPアドレスを参照）
# ----------------------
resource "aws_customer_gateway" "cgw_01" {
  bgp_asn    = local.gcp_vpn_config.asn
  ip_address = google_compute_ha_vpn_gateway.vpn_gw.vpn_interfaces[0].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "${local.env}-${local.project}-cgw-01"
  }
}

resource "aws_customer_gateway" "cgw_02" {
  bgp_asn    = local.gcp_vpn_config.asn
  ip_address = google_compute_ha_vpn_gateway.vpn_gw.vpn_interfaces[1].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "${local.env}-${local.project}-cgw-02"
  }
}

# ----------------------
# Site-to-site connection
# ステップ5: AWS側のVPN接続を作成（時間がかかる可能性があります）
# ----------------------
resource "aws_vpn_connection" "vpn_connection_01" {
  vpn_gateway_id           = aws_vpn_gateway.vgw.id
  customer_gateway_id      = aws_customer_gateway.cgw_01.id
  type                     = "ipsec.1"
  local_ipv4_network_cidr  = "0.0.0.0/0"
  remote_ipv4_network_cidr = "0.0.0.0/0"
  tags = {
    Name = "${local.env}-${local.project}-connection-01"
  }
}

resource "aws_vpn_connection" "vpn_connection_02" {
  vpn_gateway_id           = aws_vpn_gateway.vgw.id
  customer_gateway_id      = aws_customer_gateway.cgw_02.id
  type                     = "ipsec.1"
  local_ipv4_network_cidr  = "0.0.0.0/0"
  remote_ipv4_network_cidr = "0.0.0.0/0"
  tags = {
    Name = "${local.env}-${local.project}-connection-02"
  }
}
