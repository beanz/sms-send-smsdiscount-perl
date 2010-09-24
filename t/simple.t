#!/usr/bin/perl -w
#
# Copyright (C) 2010 by Mark Hindess

use strict;
use Test::More tests => 13;
use IO::Socket::INET;
use IO::Select;

eval { require SMS::Send; };
my $has_sms_send = !$@;
SKIP: {
  skip 'SMS::Send not available', 13 unless $has_sms_send;

  use_ok('SMS::Send::SMSDiscount');
  use_ok('SMS::Send');
  my $sms = SMS::Send->new('SMSDiscount',
                           _login => 'test', _password => 'pass',
                           _verbose => 0);
  ok($sms, 'SMS::Send->new with SMSDiscount driver');

  my $serv = IO::Socket::INET->new(Listen => 1, LocalAddr => 'localhost',
                                   LocalPort => 0);
  skip 'Failed to set up fake HTTP server', 10 unless ($serv);
  my $pid = fork;
  unless ($pid) { server($serv); }
  $SMS::Send::SMSDiscount::URL =
    'http://'.$serv->sockhost.':'.$serv->sockport.'/';
  $serv->close;
  ok(my $ret = $sms->send_sms(text => 'text1', to => '+441234654321'),
     'SMSDiscount successful message');
  ok(!$sms->send_sms(text => 'text2', to => '+441234654321'),
     'SMSDiscount unsuccessful message');
  ok(!$sms->send_sms(text => 'text3', to => '+441234654321'),
     'SMSDiscount HTTP error');

  $sms = SMS::Send->new('SMSDiscount', _login => 'test', _password => 'pass');
  ok($sms, 'SMS::Send->new with SMSDiscount driver - verbose');

  my $res;
  is(test_warn(sub {
                 $res = $sms->send_sms(text => 'text4', to => '+441234654321'),
               }),
     "Failed: Oops\n",
     'SMSDiscount unsuccessful message warning');
  ok(!$res, 'SMSDiscount unsuccessful message w/verbose mode');

  like(test_warn(sub {
                   $sms->send_sms(text => 'text5', to => '+441234654321'),
                 }),
     qr/^HTTP failure: HTTP\/1\.0 402 Payment required/,
     'SMSDiscount HTTP error warning');
  ok(!$res, 'SMSDiscount HTTP error w/verbose mode');

  waitpid $pid, 0;
  undef $SMS::Send::SMSDiscount::URL;

  is(test_error(sub { SMS::Send->new('SMSDiscount') }),
     "SMS::Send::SMSDiscount->new requires _login parameter\n",
     'requires _login parameter');
  is(test_error(sub { SMS::Send->new('SMSDiscount', _login => 'test') }),
     "SMS::Send::SMSDiscount->new requires _password parameter\n",
     'requires _password parameter');

}

sub server {
  my $serv = shift;
  my $sel = IO::Select->new($serv);
  my $client;
  my $sel2;
  my $count = 1;

  foreach my $resp
    (q{HTTP/1.0 200 OK\nContent-Type: text/html\n
<?phpxml version="1.0" encoding="utf-8"?>
<SmsResponse>
        <version>1</version>
        <result>1</result>
        <resultstring>success</resultstring>
        <description></description>
        <endcause></endcause>
</SmsResponse>
},
     q{HTTP/1.0 200 OK\nContent-Type: text/html\n
<?phpxml version="1.0" encoding="utf-8"?>
<SmsResponse>
        <version>1</version>
        <result>0</result>
        <resultstring>failure</resultstring>
        <description>Sorry, you do not have enough credit to send this sms. Go to your accountpage to buy credit!</description>
        <endcause>1</endcause>
</SmsResponse>
},
     "HTTP/1.0 402 Payment required\nContent-Type: text/plain\n\nOops\n",
     "HTTP/1.0 200 OK\nContent-Type: text/plain\n\nOops\n",
     "HTTP/1.0 402 Payment required\nContent-Type: text/plain\n\nOops\n",
    ) {

    $sel->can_read(1) or die "Failed to receive connection\n";
    $client = $serv->accept;
    $sel2 = IO::Select->new($client);
    $sel2->can_read(1) or die "Failed to receive request\n";
    my $got;
    my $bytes = $client->sysread($got, 1500);
    match($got, 'header', qr!^(.+?)\r?\n!, 'POST / HTTP/1.1');
    match($got, 'Content-Type', qr!Content-Type: ([^\n\r]+)\r?\n!,
          'application/x-www-form-urlencoded');
    match($got, 'Content-Length', qr!Content-Length: ([^\n\r]+)\r?\n!,
          '57');
    match($got, 'password', qr!password=(.*?)([\r\n;&]|$)!, 'pass');
    match($got, 'username', qr!username=(.*?)([\r\n;&]|$)!, 'test');
    match($got, 'to', qr!to=(.*?)([\r\n;&]|$)!, '%2B441234654321');
    match($got, 'text', qr!text=(.*?)([\r\n;&]|$)!, 'text'.$count++);
    $client->syswrite($resp);
    $client->close;
  }

  exit;
}

sub match {
  my $text = shift;
  my $name = shift;
  my $re = shift;
  my $expect = shift;
  unless ($text =~ $re) {
    die "Request didn't match: $name\n";
  }
  my $actual = $1;
  unless ($expect eq $actual) {
    die "Request had $name with '$actual' not '$expect'\n";
  }
  return 1;
}

=head2 C<test_error($code_ref)>

This method runs the code with eval and returns the error.  It strips
off some common strings from the end of the message including any "at
<file> line <number>" strings and any "(@INC contains: .*)".

=cut

sub test_error {
  my $sub = shift;
  eval { $sub->() };
  my $error = $@;
  if ($error) {
    $error =~ s/\s+at (\S+|\(eval \d+\)(\[[^]]+\])?) line \d+\.?\s*$//g;
    $error =~ s/\s+at (\S+|\(eval \d+\)(\[[^]]+\])?) line \d+\.?\s*$//g;
    $error =~ s/ \(\@INC contains:.*?\)$//;
  }
  return $error;
}

=head2 C<test_warn($code_ref)>

This method runs the code with eval and returns the warning.  It strips
off any "at <file> line <number>" specific part(s) from the end.

=cut

sub test_warn {
  my $sub = shift;
  my $warn;
  local $SIG{__WARN__} = sub { $warn .= $_[0]; };
  eval { $sub->(); };
  die $@ if ($@);
  if ($warn) {
    $warn =~ s/\s+at (\S+|\(eval \d+\)(\[[^]]+\])?) line \d+\.?\s*$//g;
    $warn =~ s/\s+at (\S+|\(eval \d+\)(\[[^]]+\])?) line \d+\.?\s*$//g;
    $warn =~ s/ \(\@INC contains:.*?\)$//;
  }
  return $warn;
}
