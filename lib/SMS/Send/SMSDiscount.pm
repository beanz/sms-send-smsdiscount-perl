package SMS::Send::SMSDiscount;

# ABSTRACT: SMS::Send driver to send via smsdiscount.com

=head1 SYNOPSIS

  # Create a testing sender
  my $send = SMS::Send->new( 'SMSDiscount',
                             _login => 'smsdiscount username',
                             _password => 'smsdiscount password' );

  # Send a message
  $send->send_sms(
     text => 'Hi there',
     to   => '+61 (4) 1234 5678',
  );

=head1 DESCRIPTION

SMS::Send driver for sending SMS messages with the SMS Discount
Software (http://www.smsdiscount.com/) service.

=cut

use 5.006;
use strict;
use warnings;
use SMS::Send::Driver;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use URI::Escape;

our @ISA = qw/SMS::Send::Driver/;
our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw();

our $URL = 'https://www.SMSDiscount.com/myaccount/sendsms.php';

=method CONSTRUCTOR

=cut

sub new {
  my $pkg = shift;
  my %p = @_;
  exists $p{_login} or die $pkg."->new requires _login parameter\n";
  exists $p{_password} or die $pkg."->new requires _password parameter\n";
  exists $p{_verbose} or $p{_verbose} = 1;
  my $self = \%p;
  bless $self, $pkg;
  $self->{_ua} = LWP::UserAgent->new();
  return $self;
}

sub send_sms {
  my $self = shift;
  my %p = @_;
  $p{to} =~ s/^\+//;
  $p{to} =~ s/[- ]//g;

#  my $u = sprintf $URL.'?username=%s&password=%s&from=%s&to=%s&text=%s',
#    map { uri_escape $_ } $self->{_login}, $self->{_password},
#      $self->{_login}, '+'.$p{to}, $p{text};

  my $response = $self->{_ua}->post($URL,
                                    {
                                     username => $self->{_login},
                                     password => $self->{_password},
                                     text => $p{text},
                                     to => '+'.$p{to},
                                    });
  unless ($response->is_success) {
    my $s = $response->as_string;
    warn "HTTP failure: $s\n" if ($self->{_verbose});
    return 0;
  }
  my $s = $response->as_string;
  $s =~ s/\r?\n$//;
  $s =~ s/^.*?\r?\n\r?\n//s;
  unless ($s =~ m!<resultstring>success</resultstring>!i) {
    warn "Failed: $s\n" if ($self->{_verbose});
    return 0;
  }
  return 1;
}

1;
__END__

=head1 SEE ALSO

SMS::Send(3), SMS::Send::Driver(3)

SMS Discount Website: http://www.smsdiscount.com/
