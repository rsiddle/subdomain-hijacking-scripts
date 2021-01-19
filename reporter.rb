require 'aws-sdk-ec2'
require 'aws-sdk-s3'
require 'fileutils'

region = 'us-east-1'
aws_profile = '<your-aws-profile-name>'
s3_bucket_logs = '<your-s3-bucket>'

ec2 = Aws::EC2::Resource.new(profile: aws_profile, region: region)

puts "Running at #{Time.now}"

instance = nil
ips = {}
safe_ips = Hash.new()

# Read in any exisiting IP addresses that may contain a hijackable subdomain
if File.exist?('safe-list.txt')
    File.readlines('safe-list.txt').each do |line|
        safe_ips[line.strip] = true
    end
end

# Record any URLs that we find in the access logs.
urls = File.open('urls.txt', 'a')

$lock = Mutex.new
$work = Queue.new
$renewable = {}

def setup
  Aws::S3::Resource.new(profile: aws_profile, region: region)
end

def bucket(n)
  s3 = setup
  s3.bucket(n)
end

def get_from_bucket
    begin
        bucket(s3_bucket_logs).objects.each do |item|
            $work.push(item)
        end
    rescue Aws::S3::Errors::ExpiredToken => e
        STDERR.puts e
    end
end

def get_from_work()
  4.times do |j|
    $workers << Thread.new do
      while $work.size > 0
        begin
            item = $work.pop

            new_dir = File.join('data')
            FileUtils.mkdir_p(new_dir)

            output_file_full_path = File.join(new_dir, item.key)
            # Check for any existing full or partial downloads. Download a new file if
            # the file sizes do not match.
            if !File.exist?(output_file_full_path) || File.exist?(output_file_full_path) && item.size != File.size?(output_file_full_path)
                response = item.get(response_target: output_file_full_path)
            end
        end
      end
    end
  end
end

# Multi-threading
$workers = []
get_from_bucket()
get_from_work()
$workers.each(&:join)

# Once finished downloading all logs, extract the data.

Dir.glob(File.join('data', '*.txt')).each do |log_file|
    File.readlines(log_file).each do |line|
        next if line == "\n"
        # Parse the Nginx Logs with RegEx
        l = line.match(/([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) \[([^]]*)\] "([^"]*)" ([^ ]*) ([^ ]*)/)
        ip_address = l[2]
        request = l[7].match(/([^ ]*) ([^ ]*) ([^ ]*)/)
        if ips[ip_address].nil?
            ips[ip_address] = Hash.new(0)
        end
        # Don't check against sites that sniff for IP information
        if request[2].match(/^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$/ix)
            ips[ip_address][request[2]] += 1
            urls.puts("#{log_file},#{request[2]}")
        end
    end
end

urls.close unless urls.nil?

ec2_private_addresses_out_of_time = []

instances = ec2.instances

# Find instances that are more than 57 minutes old so we can queue them.
instances.each do |i|
    if i.launch_time < (Time.now.utc - (57 * 60))
        if i.state.name != 'terminated'
            ec2_private_addresses_out_of_time << i.private_dns_name
        end
    end
end

ips.each do |int_ip, values|
    if values.keys.size > 0
        safe_ips[int_ip] = true
    end
end

File.open('safe-list.txt', 'w') do |file|
    safe_ips.each do |k,v|
        file.puts(k)
    end
end

# # Remove IP addresses for deletion that are only in both lists.
to_remove = ec2_private_addresses_out_of_time - safe_ips.keys

instances.each do |i|
    if  i.tags.select { |t| t['key'] == 'Name' && t['value'] == 'Bootstrapper' }.size > 0
        # Ignore it.
    elsif i.state.name == "stopped"
        i.start
    elsif safe_ips[i.private_dns_name].nil? && to_remove.include?(i.private_dns_name) && i.state.name != 'terminated'
        puts "Terminating: #{i.private_dns_name}"
        i.terminate
    elsif safe_ips[i.private_dns_name] == true
        if i.tags.select { |t| t['key'] == 'Exploit' }.size == 0
            i.create_tags(tags: [{ key: 'Exploit', value: 'true' }])
        end
    else
        # On-going, no information required.
    end
end

