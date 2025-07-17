variable "repository_names" {
  type        = set(string)
  default     = [
    "algorithms/algorithmimage",
    "evaluation/method",
    "workstations/workstationimage",
  ]
  description = "The names of the repositories"
}

variable "name_prefix" {
  description = "The prefix for the resource names"
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain cluster logs"
}

variable "stopped_events_queue_arn" {
  type        = string
  description = "The ARN of the queue that stopped events should be sent to"
}

variable "logs_bucket_name" {
  type        = string
  description = "The name of the bucket for S3 logs"
}

variable "logs_bucket_arn" {
  type        = string
  description = "The ARN of the bucket for S3 logs"
}

variable "vpc_cidr_block" {
  type        = string
  default     = "172.31.0.0/16"
  description = "The CIDR block for the components VPC"
}

variable "allowed_instance_types" {
  type = set(string)
  default = [
    "ml.m5.large",
    "ml.m5.xlarge",
    "ml.m5.2xlarge",
    "ml.m5.4xlarge",
    "ml.g4dn.xlarge",
    "ml.g4dn.2xlarge",
    "ml.g4dn.4xlarge",
    "ml.p3.2xlarge",
    "ml.g5.xlarge",
    "ml.g5.2xlarge",
    "ml.p2.xlarge",
    "ml.m7i.large",
    "ml.r7i.large",
    "ml.r7i.xlarge",
    "ml.r7i.2xlarge",
    "ml.r7i.4xlarge",
    "ml.r7i.8xlarge",
    "ml.r7i.12xlarge",
    "ml.r7i.16xlarge",
    "ml.r7i.24xlarge",
    "ml.r7i.48xlarge",
  ]
  description = "The instance types allowed for the training jobs"
}

variable "maximum_runtime_seconds" {
  type        = number
  default     = 24 * 60 * 60
  description = "The maximum timeout for the training jobs"
}
