package DataDog::DogStatsd;

#use 5.010;
use strict;
use warnings;
use Carp;

use IO::Socket::INET;

use Time::HiRes qw( gettimeofday tv_interval );

use Data::Dumper;

my $debug = 0;

# = Statsd: A DogStatsd client (https://www.datadoghq.com)
#
# @example Set up a global Statsd client for a server on localhost:8125
#   require 'statsd'
#   $statsd = Statsd.new 'localhost', 8125
# @example Send some stats
#   $statsd.increment 'page.views'
#   $statsd.timing 'page.load', 320
#   $statsd.gauge 'users.online', 100
# @example Use {#time} to time the execution of a block
#   $statsd.time('account.activate') { @account.activate! }
# @example Create a namespaced statsd client and increment 'account.activate'
#   statsd = Statsd.new('localhost').tap{|sd| sd.namespace = 'account'}
#   statsd.increment 'activate'
sub new 
{
	my $classname = shift;
	my $class = ref( $classname ) || $classname;
	my %p = @_;
	
	my $self = {
		host => $p{'host'} || '127.0.0.1',
		port => $p{'port'} || 8125,
		namespace => undef,
	};
	bless( $self, $class );

	$debug = $self->{'debug'};
	
	$self->_init(); 
	
	return $self;
}

sub DESTROY 
{
	my $self = shift;
	# printf("$self dying at %s\n", scalar localtime);
}

sub _init
{
  my $self = shift;
  # init stuff, do stuff ...
  $self->{'prefix'} = '';

  $self->{'_socket'} = IO::Socket::INET->new( PeerAddr => $self->{'host'},
                                              PeerPort => $self->{'port'},
                                              Proto    => 'udp');
}

sub namespace
{
	my $self = shift;
  $self->{'namespace'} = $self->{'prefix'} = shift;
}

# Sends an increment (count = 1) for the given stat to the statsd server.
#
# @param [String] stat stat name
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
# @see #count
sub increment
{
	my $self = shift;
	my $stat = shift;
  my $opts = shift || {};
  $self->count( $stat, 1, $opts );
}

# Sends a decrement (count = -1) for the given stat to the statsd server.
#
# @param [String] stat stat name
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
# @see #count
sub decrement
{
	my $self = shift;
	my $stat = shift;
  my $opts = shift || {};
  $self->count( $stat, -1, $opts );
}

# Sends an arbitrary count for the given stat to the statsd server.
#
# @param [String] stat stat name
# @param [Integer] count count
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
sub count
{
	my $self  = shift;
	my $stat  = shift;
  my $count = shift; 
  my $opts  = shift || {};
  $self->send_stats( $stat, $count, 'c', $opts );
}

# Sends an arbitary gauge value for the given stat to the statsd server.
#
# This is useful for recording things like available disk space,
# memory usage, and the like, which have different semantics than
# counters.
#
# @param [String] stat stat name.
# @param [Numeric] gauge value.
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
# @example Report the current user count:
#   $statsd.gauge('user.count', User.count)
##def gauge(stat, value, opts={})
##	send_stats stat, value, :g, opts
##end
sub gauge
{
	my $self  = shift;
	my $stat  = shift;
  my $value = shift; 
  my $opts  = shift || {};
  $self->send_stats( $stat, $value, 'g', $opts );
}

# Sends a value to be tracked as a histogram to the statsd server.
#
# @param [String] stat stat name.
# @param [Numeric] histogram value.
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
# @example Report the current user count:
#   $statsd.histogram('user.count', User.count)
##def histogram(stat, value, opts={})
##	send_stats stat, value, :h, opts
##end
sub histogram
{
	my $self  = shift;
	my $stat  = shift;
  my $value = shift; 
  my $opts  = shift || {};
  $self->send_stats( $stat, $value, 'h', $opts );
}

# Sends a timing (in ms) for the given stat to the statsd server. The
# sample_rate determines what percentage of the time this report is sent. The
# statsd server then uses the sample_rate to correctly track the average
# timing for the stat.
#
# @param [String] stat stat name
# @param [Integer] ms timing in milliseconds
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
##def timing(stat, ms, opts={})
##	send_stats stat, ms, :ms, opts
##end
sub timing
{
	my $self = shift;
	my $stat = shift;
  my $ms   = shift; 
  my $opts = shift || {};
  $self->send_stats( $stat, $ms, 'ms', $opts );
}

# Reports execution time of the provided block using {#timing}.
#
# @param [String] stat stat name
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
# @yield The operation to be timed
# @see #timing
# @example Report the time (in ms) taken to activate an account
#   $statsd.time('account.activate') { @account.activate! }
##def time(stat, opts={})
##	start = Time.now
##	result = yield
##	timing(stat, ((Time.now - start) * 1000).round, opts)
##	result
##end

# Sends a value to be tracked as a set to the statsd server.
#
# @param [String] stat stat name.
# @param [Numeric] set value.
# @param [Hash] opts the options to create the metric with
# @option opts [Numeric] :sample_rate sample rate, 1 for always
# @option opts [Array<String>] :tags An array of tags
# @example Record a unique visitory by id:
#   $statsd.set('visitors.uniques', User.id)
##def set(stat, value, opts={})
##	send_stats stat, value, :s, opts
##end
sub set
{
	my $self  = shift;
	my $stat  = shift;
  my $value = shift; 
  my $opts  = shift || {};
  $self->send_stats( $stat, $value, 's', $opts );
}

sub send_stats
{
	my $self  = shift;
	my $stat  = shift;
  my $delta = shift;
  my $type  = shift;
  my $opts  = shift || {};

  my $sample_rate = defined $opts->{'sample_rate'} ? $opts->{'sample_rate'} : 1;
  if( $sample_rate == 1 )
	{
      $stat =~ s/::/./g;
			$stat =~ s/[:|@]/_/g;
      my $rate = '';
      $rate = "|\@${sample_rate}" unless $sample_rate == 1;
      my $tags = '';
      $tags = "|#".join(',',@{$opts->{'tags'}}) if $opts->{'tags'};
			my $message = $self->{'prefix'}."${stat}:${delta}|${type}${rate}${tags}";
			#print $message."\n";
      $self->send_to_socket( $message );
	}
}

sub send_to_socket
{
	my $self = shift;
	my $message = shift;
  my $ret = $self->{'_socket'}->send( $message );
	#print "Return from send :$ret:\n";
}
1;

