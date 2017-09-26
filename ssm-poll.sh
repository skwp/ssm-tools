#!/usr/bin/env bash

set -e

# Note: make a file called "ssm-script" with your script
# This script requires execution priveleges on the  AWS-RunShellScript SSM Command

PATH_TO_SCRIPT=$1

if [[ -z "$PATH_TO_SCRIPT" ]]; then
  echo "Usage: ./ssm-poll.sh myscript.sh"
fi

COMMAND=$(cat $PATH_TO_SCRIPT | tr '\n' ';')

OUTPUT_OPTIONS="--output-s3-bucket-name $S3_OUTPUT --output-s3-key-prefix $PATH_TO_SCRIPT"
POLLING_TIME=1

function wait_for_ssm_command() {
  command_id=$1

  # if invocation is blank
  while true
  do
    invocation=$(aws ssm list-command-invocations --command-id $command_id | jq -r '.CommandInvocations[0]')

    if [[ -z "$invocation" ]]; then
      echo "Didn't find any results for this command, sleeping until we see a result."
      sleep $POLLING_TIME
    else
      status=$(echo $invocation | jq -r '.StatusDetails')

      if [[ $status == "InProgress" ]]; then
        echo "Command in progress, waiting..."
        sleep $POLLING_TIME
      elif [[ $status == "Success" ]]; then
        echo "Success! Output: $(echo $invocation | jq -r '.StandardOutputUrl')"
        exit 0
      else
        echo "Error! Status: $status; Output at: $(echo $invocation | jq -r '.StandardErrorUrl')"
        exit 1
      fi
    fi
  done
}

echo "Executing command..."
out=$(aws ssm send-command --document-name "AWS-RunShellScript" --parameters "{\"commands\":[\"$COMMAND\"]}" --region us-east-1 $PROFILE --targets $TARGETS $OUTPUT_OPTIONS --max-errors 1)

command_id=$(echo $out | jq -r '.Command.CommandId')
wait_for_ssm_command $command_id
