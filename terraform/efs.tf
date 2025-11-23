# EFS File System for MBTiles
resource "aws_efs_file_system" "mbtiles" {
  creation_token = "${var.project_name}-mbtiles-efs"
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  
  tags = {
    Name = "${var.project_name}-mbtiles"
  }
}

# EFS Mount Targets (one per AZ)
resource "aws_efs_mount_target" "mbtiles_az1" {
  file_system_id  = aws_efs_file_system.mbtiles.id
  subnet_id       = aws_default_subnet.default_az1.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "mbtiles_az2" {
  file_system_id  = aws_efs_file_system.mbtiles.id
  subnet_id       = aws_default_subnet.default_az2.id
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point for Lambda
resource "aws_efs_access_point" "lambda_mbtiles" {
  file_system_id = aws_efs_file_system.mbtiles.id
  
  posix_user {
    gid = 1000
    uid = 1000
  }
  
  root_directory {
    path = "/mbtiles"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }
  
  tags = {
    Name = "${var.project_name}-lambda-access"
  }
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_default_vpc.default.id
  
  ingress {
    description     = "NFS from Lambda"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-efs-sg"
  }
}

# Security Group for Lambda
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda"
  vpc_id      = aws_default_vpc.default.id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}
