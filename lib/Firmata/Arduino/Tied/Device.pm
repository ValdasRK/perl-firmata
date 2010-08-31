package Firmata::Arduino::Tied::Device;

use strict;
use Time::HiRes qw/time/;
use Firmata::Arduino::Tied::Constants qw/ :all /;
use Firmata::Arduino::Tied::IO;
use Firmata::Arduino::Tied::Protocol;
use Firmata::Arduino::Tied::Base
    ISA => 'Firmata::Arduino::Tied::Base',
    FIRMATA_ATTRIBS => {

# Object handlers
        io               => undef,
        protocol         => undef,

# Used for internal tracking of events/parameters
        protocol_version => undef,
        sysex_mode       => undef,
        sysex_data       => [],

# For the status of individual pins
        pins             => {},

# For information about the device. eg: firmware version
        metadata         => {},
    };

sub open {
# --------------------------------------------------
# Connect to the IO port and do some basic operations
# to find out how to connect to the device
#
    my ( $pkg, $port, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

    $self->{io}       = Firmata::Arduino::Tied::IO->open($port);
    $self->{protocol} = Firmata::Arduino::Tied::Protocol->new;

    return $self;
}

sub messages_handle {
# --------------------------------------------------
# Receive identified message packets and convert them
# into their appropriate structures and parse
# them as required
#
    my ( $self, $messages ) = @_;

    return unless $messages;
    return unless @$messages;

# Now, handle the messages
    my $proto  = $self->{protocol};
    for my $message ( @$messages ) {
        my $command = $message->{command_str};
        my $data    = $message->{data};

        COMMAND_HANDLE: {

# Handle pin messages
            $command eq 'DIGITAL_MESSAGE' and do {
                $self->{pins}{digital} = 1;
            };

# Handle metadata information
            $command eq 'REPORT_VERSION' and do {
                $self->{metadata}{firmware_version} = sprintf "V_%i_%02i", @$data;
                last;
            };

# SYSEX handling
            $command eq 'START_SYSEX' and do {
                last;
            };
            $command eq 'DATA_SYSEX' and do {
                last;
            };
            $command eq 'END_SYSEX' and do {
                last;
            };

        };

use Data::Dumper; warn Dumper $self;
        print "$command : \n";
    }

}

sub probe {
# --------------------------------------------------
# Request the version of the protocol that the
# target device is using. Sometimes, we'll have to
# wait a couple of seconds for the response so we'll
# try for 2 seconds and rapidly fire requests if 
# we don't get a response quickly enough ;)
#
    my ( $self ) = @_;

    my $proto  = $self->{protocol};
    my $io     = $self->{io};
    $self->{metadata}{firmware_version} = '';

# Wait for 10 seconds only
    my $end_tics = time + 10;

# Query every .5 seconds
    my $query_tics = time;
    while ( $end_tics >= time ) {

        if ( $query_tics <= time ) {
# Query the device for information on the firmata firmware_version
            my $query_packet = $proto->packet_query_version;
            $io->data_write($query_packet) or die "OOPS: $!";
            $query_tics = time + 0.5;
        };

# Try to get a response
        my $buf = $io->data_read(100) or do {
                        select undef, undef, undef, 0.1;
                        next;
                    };
        my $messages = $proto->message_data_receive($buf);

# Start handling the messages
        $self->messages_handle($messages);

        if ( $self->{metadata}{firmware_version} ) {
            return $self->{metadata}{firmware_version};
        }
    }

}


1;