require 'aws-sdk-ec2'

puts "Running at #{Time.now}"

###
# Modify these parameters
###

instance_limit = 500 # Number of EC2 instances.
region = 'us-east-1'
availability_zone = 'us-east-1a'
instance_type = 't2.small'
aws_profile = '<your-aws-profile-name>'
security_group_name = 'EC2SSHOpen2'
base_instance_name = 'Bootstrapper'
security_group_description = 'Temporary Security Group SSH/HTTP/HTTPS exposed to all.'
ssh_key_name = '<your-ssh-key>'

###
# Do not modify
###

ec2 = Aws::EC2::Resource.new(profile: aws_profile, region: region)
time_start = Time.now.to_i
instances = ec2.instances
base_instance = nil
instance_count = 0

###
# Setup Security Groups
###

security_group = nil
security_groups = ec2.security_groups.select { |sg| sg.group_name == security_group_name }
if security_groups.size > 0
    security_group = security_groups.first
else
    security_group = ec2.create_security_group({
        group_name: security_group_name,
        description: 'Security group for testing',
    })

    security_group.authorize_ingress({
        ip_permissions: [{
            ip_protocol: 'tcp',
            from_port: 22,
            to_port: 22,
            ip_ranges: [{
                cidr_ip: '0.0.0.0/0'
            }]
        }, {
            ip_protocol: 'tcp',
            from_port: 80,
            to_port: 80,
            ip_ranges: [{
                cidr_ip: '0.0.0.0/0'
            }],
        }, {
            ip_protocol: 'tcp',
            from_port: 443,
            to_port: 443,
            ip_ranges: [{
                cidr_ip: '0.0.0.0/0'
            }]
        }]
    })
end

###
# Setup Keypairs
###

key_pair = nil
key_pairs = ec2.key_pairs.select { |sg| sg.key_name == ssh_key_name }
if key_pairs.size > 0
    key_pair = key_pairs.first
else
    key_pair = ec2.create_key_pair(key_name: ssh_key_name)
    File.open("#{ssh_key_name}.pem", 'w') do |f|
        f.puts key_pair.key_material
    end
end

###
# Bootstrapped Instance
###

instances.each do |i|
    if %[running pending stopped].include?(i.state.name)
        if i.tags.size > 0 && i.tags.select { |t| t.key == 'Name' && t.value[base_instance_name] }
            base_instance = i
            instance_count += 1
        end
    end
end

###
# Create Bootstrapped Instance (If it doesn't exist)
###

image_id = nil
if !base_instance.nil?
    begin
      image_id = base_instance.create_image(name: 'Bootstraper').id
      puts "Creating AMI. Re-run '#{File.basename(__FILE__)}'"
      exit(0)
    rescue Aws::EC2::Errors::InvalidAMINameDuplicate => e
      image_id = e.message.match(/ami-([a-zA-Z0-9]*)/)[0]
    rescue => e
        binding.pry
    end
else
    results = ec2.create_instances({
        image_id: 'ami-0947d2ba12ee1ff75', # Default Amazon Linux 2 AMI (HVM), SSD Volume Type
        min_count: 1,
        max_count: 1,
        key_name: key_pair.key_name,
        security_group_ids: [security_group.id],
        instance_type: instance_type,
        placement: {
            availability_zone: availability_zone
        }
    })
    puts "Creating instances. Please wait, it may take a minute or two..."
    ec2.client.wait_until(:instance_status_ok, {instance_ids: results.map(&:id)})
    results.each do |result|
        result.create_tags(tags: [{ key: 'Name', value: base_instance_name }])
        puts "Modify the server then re-run '#{File.basename(__FILE__)}'"
        puts "Secure your SSH key by making it read only:"
        puts "chmod 400 #{key_pair.key_name}.pem"
        puts "ssh -i #{key_pair.key_name}.pem ec2-user@#{ec2.instance(result.instance_id).public_dns_name}"
    end
    exit(0)
end

amount = (instance_limit - instance_count)

if amount > 0
    results = ec2.create_instances({
    image_id: image_id,
    min_count: amount,
    max_count: amount,
    key_name: key_pair.key_name,
    security_group_ids: [security_group.id],
    instance_type: instance_type,
    placement: {
        availability_zone: availability_zone
    }
    })

    i = 0

    results.each do |result|
        result.create_tags(tags: [{ key: 'Name', value: "Test-#{time_start}-#{i}" }])
        i += 1
    end
end
