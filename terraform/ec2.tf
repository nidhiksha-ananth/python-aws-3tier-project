
# Launch template for Flask application servers
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-app-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  depends_on = [
    aws_iam_role_policy.rds_secret_access
  ]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(
    templatefile("${path.module}/user_data.sh", {
      db_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
      aws_region    = var.aws_region
      project_name  = var.project_name
      db_name       = var.db_name
    })
  )

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  # Require IMDSv2 for instance metadata access
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Encrypted root volume
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-app-server"
    }
  }
}
