#!/usr/bin/env ruby

# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation; either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.

require_relative 'shortbus'
require_relative 'grue'

require 'ruby-duration'

# Regular expression to match an irc nick pattern (:nick[!user@host])
# and capture the nick portion in \1
NICKRE = /^:([^!]*)!.*/

# Match beanfootage's tinyurl output
TINYURL_REGEX = /^(:)?\[AKA\]/

MAX_MESSAGE_LENGTH = 1024

# ShortBus plugin to name/shame url reposters
class GrueShortBus < ShortBus
  # Constructor
  def initialize()
    super

    # Expression to match an action/emote message
    @ACTION = /^\001ACTION(.*)\001/

    @grue = Grue.new()
    @grue.load()
    @channels = []
    @hooks = []
    hook_command( 'GRUE', XCHAT_PRI_NORM, method( :enable), '')
    hook_command( 'GRUEDUMP', XCHAT_PRI_NORM, method( :dump), '')
    hook_server( 'Disconnected', XCHAT_PRI_NORM, method( :disable))
    hook_server( 'Notice', XCHAT_PRI_NORM, method( :notice_handler))
    # Don't check these for gruings yet
    # hook_server( 'Quit', XCHAT_PRI_NORM, method( :quit_handler))
    # hook_server( 'Part', XCHAT_PRI_NORM, method( :process_message))
    # hook_server( 'Kick', XCHAT_PRI_NORM, method( :kick_handler))
    puts('Grue loaded. Run /GRUE #channel to enable.')
  end # initialize

  # Enables the plugin
  def enable(words, words_eol, data)
    if (words.size < 2)
      if (@hooks.empty?)
        puts('Usage: GRUE #channel [channel2 ...]')
        return XCHAT_EAT_ALL
      else
        disable()
      end
    end

    begin
      if ([] == @hooks)
        @hooks << hook_server('PRIVMSG', XCHAT_PRI_NORM, method(:process_message))
        @hooks << hook_print('Your Message', XCHAT_PRI_NORM, method(:your_message))
        @hooks << hook_print('Your Action', XCHAT_PRI_NORM, method(:your_action))
      end

      1.upto(words.size-1){ |i|
        if (@channels.select{ |item| item == words[i] }.empty?)
          @channels << words[i]
          puts("Monitoring #{words[i]}")
        else
          @channels -= [words[i]]
          puts("Ignoring #{words[i]}")
        end
      }
    rescue
      # puts("#{caller.first}: #{$!}")
    end

    return XCHAT_EAT_ALL
  end # enable

  # Disables the plugin
  def disable(words=nil, words_eol=nil, data=nil)
    begin
      if (@hooks.empty?)
        puts('Grue already disabled.')
      else
        @hooks.each{ |hook| unhook(hook) }
        @hooks = []
        dump(nil, nil, nil)
        puts('Grue disabled.')
      end
    rescue
      # puts("#{caller.first}: #{$!}")
    end

    return XCHAT_EAT_ALL
  end # disable

  # Dumps the url cache to disk
  def dump(words, words_eol, data)
    @grue.dump()
  end # dump

  # Check for disconnect notice
  def notice_handler(words, words_eol, data)
    begin
      if (words_eol[0].match(/(^Disconnected|Lost connection to server)/))
        disable()
      end
    rescue
      # puts("#{caller.first}: #{$!}")
    end

    return XCHAT_EAT_NONE
  end # notice_handler

  # Process quit messages
  def quit_handler(words, words_eol, data)
    begin
      if (3 < words.size)
        words[2] = get_info('channel')
        process_message(words, words_eol, data)
      end
    rescue
    end
  end # quit_handler

  # Process kick messages
  def kick_handler(words, words_eol, data)
    begin
      if (3 < words.size)
        words.slice!(3)
        3.upto(words_eol.size-1){ |i|
          words_eol[i].sub!(/^[^\s]+\s+/, '')
        }
      end
      return process_message(words, words_eol, data)
    rescue
    end
  end # kick_handler

  # Processes outgoing actions
  # (Really formats the data and hands it to process_message())
  # * param words [Mynick, mymessage]
  # * param data Unused
  # * returns XCHAT_EAT_NONE
  def your_action(words, data)
    words[1] = "\001ACTION#{words[1]}\001"
    return your_message(words, data)
  end # your_action

  # Processes outgoing messages
  # (Really formats the data and hands it to process_message())
  # * param words [Mynick, mymessage]
  # * param data Unused
  # * returns XCHAT_EAT_NONE
  def your_message(words, data)
    rv = XCHAT_EAT_NONE

    begin
      channel = get_info('channel')
      # Don't catch the outgoing 'Joe grued Jane's link from blah'
      if (/^([^ ]+\s?grued )[^ ]+ link from/.match(words[1]) || !@channels.detect{ |item| item == channel }) then return XCHAT_EAT_NONE; end

      words_eol = []
      # Build an array of the format process_message expects
      newwords = [words[0], 'PRIVMSG', channel] + (words - [words[0]])

      # puts("Outgoing message: #{words.join(' ')}")

      # Populate words_eol
      1.upto(newwords.size){ |i|
        words_eol << (i..newwords.size).inject(''){ |str, j|
          "#{str}#{newwords[j-1]} "
        }.strip()
      }

      rv = process_message(newwords, words_eol, data)
    rescue
      # puts("#{caller.first}: #{$!}")
    end

    return rv
  end # your_message

  # Processes an incoming server message
  # * words[0] -> ':' + user that sent the text
  # * words[1] -> PRIVMSG
  # * words[2] -> channel
  # * words[3..(words.size-1)] -> ':' + text
  # * words_eol is the joining of each array of words[i..words.size]
  # * (e.g. ["all the words", "the words", "words"]
  def process_message(words, words_eol, data)
    begin
      sometext = ''
      outtext = ''
      nick = words[0].sub(NICKRE,'\1')
      storekey = nil
      index = 0
      line = nil
      channel = words[2]

      # Strip intermittent trailing @ word
      if (words.last == '@')
        words.pop()
        words_eol.collect!{ |w| w.gsub(/\s+@$/,'') }
      end

      if (!@channels.detect{ |item| item == channel } ||
          words_eol.size < 4 ||
          words_eol[3].match(TINYURL_REGEX))
        return XCHAT_EAT_NONE
      end

      # puts("Processing message: #{words_eol[3]}")

      response = @grue.process_statement(channel, nick, words_eol[3])

      # puts("Response #{response} (size #{response.size})")

      if (response && response.size > 1)
        puts("Shaming #{nick} on #{channel}")
        output_shame(channel, nick, response)
      end
    rescue
      # puts("#{caller.first}: #{$!}")
    end

    return XCHAT_EAT_NONE
  end # process_message

  # Sends a shaming message
  # * nick is the nick of the user who sent the duplicate url
  # * results are the results of the lookup
  def output_shame(channel, nick, results)
    originick = results[0][1]
    duration = Duration.new(Time.now - results[0][2]).format("%td %~d %h %~h %m %~m %s %~s")
    duplicates = results.size - 2
    sometext = ''

    if (originick.casecmp(nick).zero?)
      sometext = "#{nick} just grued its own link from #{duration} ago!"
    else
      sometext = "#{nick} just grued #{originick}'s link from #{duration} ago!"
    end
    if (duplicates > 0)
      sometext += " (#{duplicates} duplicates)"
    end

    command("MSG #{channel} #{GrueShortBus.ellipsize(sometext)}")
  end # output_shame

  def GrueShortBus.ellipsize(str)
    (MAX_MESSAGE_LENGTH < str.size) ?
      "#{str.slice(0, MAX_MESSAGE_LENGTH)}..." :
      str
  end # ellipsize
end # GrueShortBus

if (__FILE__ == $0)
  blah = GrueShortBus.new()
  blah.run()
end
