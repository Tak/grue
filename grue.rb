#!/usr/bin/env ruby
# encoding: utf-8

# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation; either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.

require_relative 'fixedqueue'
require_relative 'urika'

require 'uri'
require 'psych'

URLS_PER_CHANNEL = 100000 # ?
CACHE = "#{ENV['HOME']}/.grue.yaml".freeze

# Manages a url database and reports repetitions
# Because hell is repetition
class Grue
  def initialize()
    @urls = {}
  end

  # Processes a statement
  # param channel The channel in which the statement was made
  # param nick The nick making the statement
  # param text The text of the statement
  # returns The entries with a matching URL (including this statement), or nil
  def process_statement(channel, nick, text)
    return nil unless (url = Urika.get_first_url(text))

    # TODO: Better/canonical timestamp?
    record_url(channel, nick, url, Time.now)

    # url, nick, datetime
    # TODO: more efficiently searchable data structure
    return @urls[channel].select { |chunk|
      chunk && chunk[0].casecmp(url).zero?
    }
  end

  # Records a url
  # param channel The channel in which the url was observed
  # param nick The nick sending the url
  # param url The url
  # param time The time the url was observed
  def record_url(channel, nick, url, time)
    @urls[channel] = FixedQueue.new(URLS_PER_CHANNEL) unless @urls[channel]
    puts "Adding url #{url} for channel #{channel}"
    @urls[channel].push([url, nick, time])
  end

  # Load the url database from CACHE
  def load()
    begin
      @urls = Psych.load_file(CACHE)
      puts "Loaded cache from #{CACHE}"
    rescue => error
      puts "Error loading #{CACHE}: #{error.to_s}"
    end
  end

  # Dump the url database to CACHE
  def dump()
    begin
      File.open(CACHE, 'w') { |file|
        file.write(Psych.dump(@urls))
      }
      puts "Successfully dumped urls to #{CACHE}"
    rescue => error
      puts "Error dumping urls: #{error.to_s}"
    end
  end
end # Grue

if (__FILE__ == $0)
  require 'test/unit'

  class GrueTest < Test::Unit::TestCase
    def setup()
      @grue = Grue.new()
    end # setup

    def test_detect_gruing
      statements = [
        [ 'wat', 'meh', 0],
        [ 'Tak', 'https://foo.bar', 1],
        [ 'Tak', 'meh', 0],
        [ 'wat', 'https://foo.bar', 2],
        [ 'wat', 'http://foo.bar', 3],
      ]

      statements.each { |thing|
        # p thing
        result = @grue.process_statement('#utter-failure', thing[0], thing[1])
        if (thing[2].zero?)
          assert(!result || result.size == 0, "Unexpected result #{result} for input #{thing[1]}")
        else
          # p result
          assert_equal(thing[2], result.size, "Unexpected match count #{result.size} for input #{thing[1]}")
        end
      }
    end
  end
end
