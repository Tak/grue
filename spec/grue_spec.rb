require 'grue'

RSpec.describe Grue do
  before(:all) do
    @grue = Grue::Grue.new()
  end

  it 'has a version number' do
    expect(Grue::VERSION).not_to be nil
  end

  it 'detects gruing' do
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
        expect(!result || result.empty?).to eq(true)
      else
        # p result
        expect(result.size).to eq(thing[2])
      end
    }
  end

  it 'correctly prints durations' do
    origin = Time.new(2017, 04, 06, 11, 17)

    offsets = [
        [origin + 1, '1 second'],
        [origin + 2, '2 seconds'],
        [origin + 11, '11 seconds'],
        [origin + 60, '1 minute'],
        [origin + 61, '1 minute'],
        [origin + 121, '2 minutes'],
        [origin + 3600, '1 hour'],
        [origin + 3601, '1 hour'],
        [origin + 3660, '1 hour'],
        [origin + 3661, '1 hour'],
        [origin + 7200, '2 hours'],
        [origin + 86400, '1 day'],
        [origin + 86401, '1 day'],
        [origin + 86461, '1 day'],
        [origin + 90001, '1 day'],
        [origin + 90061, '1 day'],
        [origin + 172800, '2 days'],
    ]

    offsets.each{ |offset|
      expect(Grue.pretty_print_duration_difference(origin, offset[0])).to eq(offset[1])
    }
  end
end
