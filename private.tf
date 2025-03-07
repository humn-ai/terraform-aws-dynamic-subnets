module "private_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["private"]
  tags = merge(
    var.private_subnets_additional_tags,
    { (var.subnet_type_tag_key) = format(var.subnet_type_tag_value_format, "private") }
  )

  context = module.this.context
}

locals {
  private_subnet_count        = var.max_subnet_count == 0 ? length(flatten(data.aws_availability_zones.available.*.names)) : var.max_subnet_count
  private_network_acl_enabled = signum(length(var.private_network_acl_id)) == 0 ? 1 : 0
  private_newbits             = var.desired_newbits == 0 ? ceil(log(local.private_subnet_count * 2, 2)) : var.desired_newbits
}

resource "aws_subnet" "private" {
  count             = local.enabled ? local.availability_zones_count : 0
  vpc_id            = join("", data.aws_vpc.default.*.id)
  availability_zone = element(var.availability_zones, count.index)

  cidr_block = cidrsubnet(
    signum(length(var.cidr_block)) == 1 ? var.cidr_block : join("", data.aws_vpc.default.*.cidr_block),
    local.private_newbits,
    count.index
  )

  tags = merge(
    module.private_label.tags,
    {
      "Name" = format("%s%s%s", module.private_label.id, local.delimiter, local.az_map[element(var.availability_zones, count.index)])
    }
  )

  lifecycle {
    # Ignore tags added by kops or kubernetes
    ignore_changes = [tags.kubernetes, tags.SubnetType]
  }
}

resource "aws_route_table" "private" {
  count  = local.enabled ? local.availability_zones_count : 0
  vpc_id = join("", data.aws_vpc.default.*.id)

  tags = merge(
    module.private_label.tags,
    {
      "Name" = format("%s%s%s", module.private_label.id, local.delimiter, local.az_map[element(var.availability_zones, count.index)])
    }
  )
}

resource "aws_route_table_association" "private" {
  count          = local.enabled ? local.availability_zones_count : 0
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_network_acl" "private" {
  count      = local.enabled ? local.private_network_acl_enabled : 0
  vpc_id     = var.vpc_id
  subnet_ids = aws_subnet.private.*.id

  egress {
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }

  ingress {
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }

  tags = module.private_label.tags
}
