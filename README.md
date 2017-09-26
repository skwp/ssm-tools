# SSM Tools

Tools to use with amazon ssm to send commands to instances

## Setup

First, add a policy to allow an IAM user or process to execute ssm commands and
specify which commands to run on which instances. Here's an example of the
setup for running SSM commands on EMR. Note that it's pretty permissive, using the
AWS-RunShellScript command, which means the user can execute arbitrary commands.
We lock down which instances can run this by using tags.

Terraform:

    data "template_file" "emr-ssm-policy" {
      # The template provides a generic ssm execution policy
      # Below, we will specify which commands can be run on which instances
      template = "${file("./policies/ssm-executor.tpl")}"
      vars {
        # Which command will be allowed to run. Note that AWS-RunShellScript is very broad and
        # can be used to execute arbitrary commands on the instance. It's better to replace
        # this with a custom script registered in SSM when possible.
        allowed_command = "arn:aws:ssm:us-east-1::document/AWS-RunShellScript"

        # Bucket where output will be stored
        bucket_name = "your-bucket-name"

        # Which EC2 instances are allowed to run the command.
        # See: http://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-rc-setting-up-cmdsec.html
        ec2_condition = <<EOF
          "Condition":{
            "StringLike":{
              "ssm:resourceTag/example":[
                "foobar"
              ],
              "ssm:resourceTag/another_tag":[
                "some_value"
              ]
            }
          }
        EOF
      }
    }

    resource "aws_iam_role_policy" "emr-ssm-executor" {
      name = "emr-ssm-executor"

      # See emr-ssm-executor.json for how we restrict to a group of instances by tag
      policy = "${data.template_file.emr-ssm-policy.rendered}"
      role = "${aws_iam_role.emr-ssm-executor.name}"
    }



ssm-executor.tpl:

     {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": [
            "ssm:ListDocuments",
            "ssm:DescribeDocument*",
            "ssm:GetDocument",
            "ssm:DescribeInstance*"
          ],
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": "ssm:SendCommand",
          "Effect": "Allow",
          "Resource": [
            "${allowed_command}"
          ]
        },
        {
          "Action": "ssm:SendCommand",
          "Effect": "Allow",
          "Resource": [
            "arn:aws:ec2:*:*:instance/*"
          ],
          ${ec2_condition}
        },
        {
          "Action": "ssm:SendCommand",
          "Effect": "Allow",
          "Resource": [
            "arn:aws:s3:::${bucket_name}/*"
          ]
        },
        {
          "Action": [
            "s3:*"
          ],
          "Effect": "Allow",
          "Resource": [
            "arn:aws:s3:::${bucket_name}/*",
            "arn:aws:s3:::${bucket_name}"
          ]
        },
        {
          "Action": [
            "ssm:List*"
          ],
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": "ec2:Describe*",
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    }

## ssm-poll

The ssm-poll.sh script is designed to execute a command and then wait for its completion. It will exit with 0 if it completes successfully.

Usage:

    S3_OUTPUT=reverb-command-output \
    PROFILE="--profile ssm-emr" \
    TARGETS="Key=tag:aws:elasticmapreduce:instance-group-role,Values=MASTER Key=tag:team,Values=data" \
    ./ssm-poll.sh ~/myscript.sh


If you don't need an IAM profile, for example if running this on an instance that already has the priveleges required, just omit it:

    ./ssm-poll.sh ~/myscript.sh
