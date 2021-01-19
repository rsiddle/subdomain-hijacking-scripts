require 'aws-sdk-ec2'
require 'aws-sdk-s3'
require 'fileutils'

region = 'us-east-1'
aws_profile = '<your-aws-profile-name>'

ec2 = Aws::EC2::Resource.new(profile: 'ryansiddle', region: region)

puts "Running at #{Time.now}"

statuses = Hash.new(0)

ec2.instances.each do |i|
  statuses[i.state.name] += 1
end

statuses.each do |s, v|
  puts "#{s} => #{v}"
end