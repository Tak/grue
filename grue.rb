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

require 'uri'

URIRE = /https?:\/\/[^\s]+/
URLS_PER_CHANNEL = 100000 # ?

class Grue
  def initialize()
    @urls = {}
  end

  def process_statement(channel, nick, text)
    return nil unless (url = Grue.get_first_url(text))

    # TODO: Better/canonical timestamp?
    record_url(channel, nick, url, Time.now)

    # url, nick, datetime
    return @urls[channel].select { |chunk|
      chunk && chunk[0].casecmp(url).zero?
    }
  end

  def record_url(channel, nick, url, time)
    @urls[channel] = FixedQueue.new(URLS_PER_CHANNEL) unless @urls[channel]
    puts "Adding url #{url} for channel #{channel}"
    @urls[channel].push([url, nick, time])
  end

  def self.get_first_url(message)
    if (match = URIRE.match(message))
      uri = URI.parse(match.to_s())
      return (uri && (uri.kind_of?(URI::HTTP) || uri.kind_of?(URI::HTTPS))) ? match.to_s() : nil
    end
    return nil
  end # get_first_url
end # Grue

if (__FILE__ == $0)
  require 'test/unit'

  class GrueTest < Test::Unit::TestCase
    def setup()
      @grue = Grue.new()
    end # setup

    def test_uri_validation
      uris = [
        [ 'http://google.com', 'http://google.com' ],
        [ 'https://google.com', 'https://google.com' ],
        [ 'htp://google.com', nil ],
        [ 'ftp://google.com', nil ],
        [ 'I would like you to see http://google.com', 'http://google.com' ],
        [ 'I would like you to see https://google.com', 'https://google.com' ],
        [ 'I would like you to see htp://google.com', nil ],
        [ 'I would like you to see ftp://google.com', nil ],
        [ 'htp://google.com https://google.com ttp://google.com', 'https://google.com' ],
        [ 'htp://google.com http://google.com ttps://google.com', 'http://google.com' ],
        [ 'https://www.google.dk/search?q=foo+bar+baz&oq=foo+bar+baz&aqs=chrome..69i57j0l5.1283j0j7&sourceid=chrome&ie=UTF-8', 'https://www.google.dk/search?q=foo+bar+baz&oq=foo+bar+baz&aqs=chrome..69i57j0l5.1283j0j7&sourceid=chrome&ie=UTF-8' ],
      ]

      uris.each { |pair|
        url = Grue.get_first_url(pair[0])
        assert_equal(pair[1], url, "Unexpected url #{url} for input #{pair[0]}")
      }
    end # test_uri_validation

    def test_detect_gruing
      statements = [
        [ 'wat', 'meh', 0],
        [ 'Tak', 'https://foo.bar', 1],
        [ 'Tak', 'meh', 0],
        [ 'wat', 'https://foo.bar', 2],
        [ 'wat', 'http://foo.bar', 1],
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
