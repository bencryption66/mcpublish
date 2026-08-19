if Rails.env.test?
  Aws.config.update(stub_responses: true, region: "us-east-1")
else
  Aws.config.update(region: ENV.fetch("AWS_REGION", "us-east-1"))
end
