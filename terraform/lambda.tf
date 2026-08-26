data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../dist"
  output_path = "${path.module}/../lambda.zip"
}

resource "aws_lambda_function" "token" {
  function_name    = "${var.project_name}-auth-token-${var.environment}"
  role             = data.aws_iam_role.lab_role.arn
  runtime          = "nodejs22.x"
  handler          = "token.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = { ENVIRONMENT = var.environment }
  }
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.project_name}-auth-authorizer-${var.environment}"
  role             = data.aws_iam_role.lab_role.arn
  runtime          = "nodejs22.x"
  handler          = "authorizer.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 5
  memory_size      = 128

  environment {
    variables = { ENVIRONMENT = var.environment }
  }
}
