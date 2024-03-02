#!/bin/bash -e

# https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/platforms-linux-extend.html

# This script is executed after the application and web server have been set up and the application has been deployed.
echo ".platform/confighooks/postdeploy/01_map_parameters_store_to_env_vars.sh executing"
echo "Running script to fetch parameter store values and add them to /opt/elasticbeanstalk/deployment/env file."

# We need to check the Elastic Beanstalk environment properties to find out
# what the path is to use for the parameter store values to fetch.
# Only the parameters under that path will be fetched, allowing each Beanstalk
# config to specify a different path if desired.
# Read the current environment properties to find the parameter store path.
readarray eb_env_vars < /opt/elasticbeanstalk/deployment/env

# Loop through the environment variables to find the parameter store path.
for i in "${eb_env_vars[@]}"
do
  if [[ $i == *"parameter_store_path"* ]]; then
    parameter_store_path=$(echo "$i" | grep -Po "([^\=]*$)")
  fi
done

# Check if the parameter store path is set.
if [ -z ${parameter_store_path+x} ]; then
  # If the parameter store path is not set, then exit and do not continue.
  echo "Error: parameter_store_path is unset on the Elastic Beanstalk environment properties.";
  echo "You must add a property named parameter_store_path with the path prefix to your SSM parameters.";
else
  # If the parameter store path is set, then continue.
  echo "Success: parameter_store_path is set to '$parameter_store_path'";

  # Get the AWS_DEFAULT_REGION from the EC2 instance metadata.
  TOKEN=$(curl -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds:21600")
  AWS_DEFAULT_REGION=$(curl -H "X-aws-ec2-metadata-token:$TOKEN" -v http://169.254.169.254/latest/meta-data/placement/region)

  # Create a copy of the environment variable file.
  cp /opt/elasticbeanstalk/deployment/env /opt/elasticbeanstalk/deployment/custom_env_var

  # Add values to the custom file
  echo "AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" >> /opt/elasticbeanstalk/deployment/custom_env_var

  # Create jq actions to parse the SSM parameters
  # The jq actions will create a key value pair for each parameter
  # This expects the parameters to be in the format /project-name/environment/parameter-name
  jq_actions=$(echo -e ".Parameters | .[] | [.Name, .Value] | \042\(.[0])=\(.[1])\042 | sub(\042${parameter_store_path}/\042; \042\042)")

  # Increase the max attempts to 15 to avoid the ThrottlingException error
  # This should get all parameters from the parameter store in the given path in one call
  AWS_MAX_ATTEMPTS=15 aws ssm get-parameters-by-path \
  --path "$parameter_store_path" \
  --with-decryption \
  --region $AWS_DEFAULT_REGION \
  | jq -r "$jq_actions" >> /opt/elasticbeanstalk/deployment/ssm_params

  # Check if parameters were retrieved
  if [[ $? -eq 0 ]];
  then
    # If the parameters were retrieved, then continue.
    echo "Success: Parameters retrieved from SSM.";
  else
    # If the parameters were not retrieved, then exit and do not continue because something went wrong.
    echo "Error: Parameters not retrieved from SSM.";
    exit 1;
  fi

  # count the number of lines in the file to check if the parameters were retrieved
  LINE_COUNT=$(wc -l < /opt/elasticbeanstalk/deployment/ssm_params)

  # if line count is less than 1, then exit and not continue
  # this is to fail the deployment if the parameters are not retrieved
  if [[ $LINE_COUNT -lt 1 ]];
  then
    # If the parameters were not retrieved, then exit and do not continue because something went wrong.
    echo "Error: Parameters not retrieved from SSM based on line count.";
    echo "Line count: $LINE_COUNT";
    exit 1;
  fi

  # Add the SSM parameters to the custom environment variable file if they don't already exist.
  while read -r line || [ -n "$line" ]; do
    # Get the parameter name before the =
    # Use sed to remove the = from the parameter name - sed 's~=~~g'
    param_name=$(echo "$line" | grep -Po "^\s*(\w*)=")
    # Check if the parameter name exists in the custom environment variable file
    if grep -q "$param_name" /opt/elasticbeanstalk/deployment/custom_env_var; then
      # The configuration from the console takes precedence over the SSM parameter
      # If the parameter already exists in the custom environment variable file, then ignore it.
      # If you want the SSM parameter to take precedence, then remove the parameter from the console.
      echo "SSM parameter already exists in custom_env_var file: $param_name"
    else
      # If the parameter does not exist in the custom environment variable file, then add it.
      echo "Adding SSM parameter to custom_env_var file: $param_name"
      echo "$line" >> /opt/elasticbeanstalk/deployment/custom_env_var
    fi
  done < /opt/elasticbeanstalk/deployment/ssm_params

  # Replace the environment variable file with the custom environment variable file.
  cp /opt/elasticbeanstalk/deployment/custom_env_var /opt/elasticbeanstalk/deployment/env

  # Remove the custom environment variable file and the SSM parameters file since they are no longer needed.
  rm -f /opt/elasticbeanstalk/deployment/custom_env_var /opt/elasticbeanstalk/deployment/ssm_params

  # Remove the backup files created by the cp command if they exist
  rm -f /opt/elasticbeanstalk/deployment/*.bak
fi

# Restart the web service to apply the new environment variables to the application.
# This is necessary because the environment variables are only read when the application is started.
echo "Restarting web service"
systemctl restart web
