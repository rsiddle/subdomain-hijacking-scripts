#!/usr/bin/env ruby

require 'csv'
require 'set'

input = ARGV[0]
uris = Set.new

if File.exist?(input)
    csvin = CSV.open(input)
    until csvin.eof?
        line = csvin.gets
        if !line.nil? && !line[1].nil?
            # Regex source: https://regexr.com/3au3g
            matched = line[1].match(/(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]/)
            unless matched.nil?
                uris.add(matched[0])
            end
        end
    end

    uris.to_a.each do |uri|
        STDOUT.puts(uri)
    end
else
    exit(1)
end