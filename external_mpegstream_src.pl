#!/usr/bin/env perl

BEGIN {
    # disable EPOLL backend
    $ENV{LIBEV_FLAGS} = 3;
}

use strict;
use warnings;

use EV;
use IPC::Open3;
use Fcntl qw(:DEFAULT);
use Symbol;
require bytes;

system('killall curl');

$EV::DIED = sub {
    EV::unloop;
    die @_;
};

# re-mux -- otherwise Pana TV DLNA complains about unsupported file when starting
# in the middle of a stream
# (not perfect... maybe it is better to manually skip to the next GOP/I-frame)

sub async_fh {
    my($fh)=@_;
    binmode($fh) or die;
    my $flags = fcntl($fh, F_GETFL, 0);
    fcntl($fh, F_SETFL, $flags | O_NONBLOCK);
}

sub log_ev_evt_flags {
    my ($evt,$desc) = @_;
    my @flags = ();
    $desc //= '';
    push @flags, 'EV::READ' if ($evt & EV::READ);
    push @flags, 'EV::WRITE' if ($evt & EV::WRITE);
    print STDERR 'EV EVT FLAGS = '.join(', ',@flags).($desc eq '' ? '' : ', '.$desc).$/;
}

my $buf_stop_size = 32768;
my $blocksize = 32768;

my $w_ffmpeg_stdin;
my $w_ffmpeg_stdout;
my $w_ffmpeg_stderr;
my $w_ffmpeg_child;

my ($ffmpeg_stdin,$ffmpeg_stdout);
my $ffmpeg_stderr = gensym;
my $ffmpeg_pid;

my $stdout_buf = '';
my $w_stdout;

my $fh_curl;
my $w_curl;
my $curl_output_buf = '';

open $fh_curl, '-|', 'curl', 'http://i5:3001/playback' or die $!;
async_fh($fh_curl);
$w_curl = EV::io $fh_curl, EV::READ, sub {
    my($w,$flags) = @_;
    log_ev_evt_flags($flags, '$w_curl');
    return unless ($flags & EV::READ);
    sysread($fh_curl,$curl_output_buf,$blocksize,bytes::length($curl_output_buf)) or die $!;
    print STDERR 'length($curl_output_buf)='.bytes::length($curl_output_buf).$/;
    if(bytes::length($curl_output_buf) >= $buf_stop_size) {
        $w_curl->stop if $w_curl->is_active;
        print STDERR '$w_curl->stop'.$/;
    }
    if(bytes::length($curl_output_buf) > 0) {
        $w_ffmpeg_stdin->start unless $w_ffmpeg_stdin->is_active;
        print STDERR '$w_ffmpeg_stdin->start'.$/;
    }
};

sub start_ffmpeg {
    print STDERR 'start_ffmpeg()'.$/;
    undef $w_ffmpeg_child;
    undef $w_ffmpeg_stdin;
    undef $w_ffmpeg_stdout;
    undef $w_ffmpeg_stderr;
    $ffmpeg_pid = open3($ffmpeg_stdin, $ffmpeg_stdout, $ffmpeg_stderr,
                    "ffmpeg -f mpegts -i - -vcodec copy -acodec copy -f mpegts -");
    async_fh($ffmpeg_stdin);
    async_fh($ffmpeg_stdout);
    async_fh($ffmpeg_stderr);
    $w_ffmpeg_child = EV::child $ffmpeg_pid, 0, sub {
        my ($w, $flags) = @_;
        log_ev_evt_flags($flags, '$w_ffmpeg_child');
        my $status = $w->rstatus;
        start_ffmpeg();
    };
    $w_ffmpeg_stdin = EV::io $ffmpeg_stdin, EV::WRITE, sub {
        my($w,$flags) = @_;
        log_ev_evt_flags($flags, '$w_ffmpeg_stdin');
        return unless ($flags & EV::WRITE);
        if(bytes::length($curl_output_buf) == 0) {
            $w_curl->start unless $w_curl->is_active;
            print STDERR '$w_curl->start'.$/;
            $w_ffmpeg_stdin->stop if $w_ffmpeg_stdin->is_active;
            print STDERR '$w_ffmpeg_stdin->stop'.$/;
            return;
        }
        my $wlen = syswrite($ffmpeg_stdin,$curl_output_buf,bytes::length($curl_output_buf));
        if($wlen) {
            $curl_output_buf = substr($curl_output_buf,$wlen);
            print STDERR 'length($curl_output_buf)='.bytes::length($curl_output_buf).$/;
        }
        if(bytes::length($curl_output_buf) < $buf_stop_size) {
            $w_curl->start unless $w_curl->is_active;
            print STDERR '$w_curl->start'.$/;
        }
    };
    $w_ffmpeg_stdout = EV::io $ffmpeg_stdout, EV::READ, sub {
        my($w,$flags) = @_;
        log_ev_evt_flags($flags, '$w_ffmpeg_stdout');
        return unless ($flags & EV::READ);
        if(!sysread($ffmpeg_stdout,$stdout_buf,$blocksize,bytes::length($stdout_buf))) {
#             $w_ffmpeg_stdout->stop;
#             print STDERR '$w_ffmpeg_stdout->stop'.$/;
            return;
        }
        print STDERR 'length($stdout_buf)='.bytes::length($stdout_buf).$/;
        if(bytes::length($stdout_buf) >= $buf_stop_size) {
            $w_ffmpeg_stdout->stop if $w_ffmpeg_stdout->is_active;
            print STDERR '$w_ffmpeg_stdout->stop'.$/;
        }
        if(bytes::length($stdout_buf) > 0) {
            $w_stdout->start unless $w_stdout->is_active;
            print STDERR '$w_stdout->start'.$/;
        }
    };
    $w_ffmpeg_stderr = EV::io $ffmpeg_stderr, EV::READ, sub {
        my($w,$flags) = @_;
        log_ev_evt_flags($flags, '$w_ffmpeg_stderr');
        return unless ($flags & EV::READ);
        my $buf;
        if(sysread($ffmpeg_stderr,$buf,1024)) {
            print STDERR $buf;
        }
    };
}

async_fh(*STDOUT);
$w_stdout = EV::io *STDOUT, EV::WRITE, sub {
    my($w,$flags) = @_;
    log_ev_evt_flags($flags, '$w_stdout');
    return unless ($flags & EV::WRITE);
    if(bytes::length($stdout_buf) == 0) {
        $w_stdout->stop if $w_stdout->is_active;
        print STDERR '$w_stdout->stop'.$/;
        $w_ffmpeg_stdout->start unless $w_ffmpeg_stdout->is_active;
        print STDERR '$w_ffmpeg_stdout->start'.$/;
        return;
    }
    my $wlen = syswrite(STDOUT,$stdout_buf,bytes::length($stdout_buf));
    die unless defined $wlen;
    if($wlen) {
        $stdout_buf = substr($stdout_buf,$wlen);
        print STDERR 'length($stdout_buf)='.bytes::length($stdout_buf).$/;
    }
    if(bytes::length($stdout_buf) < $buf_stop_size) {
        $w_ffmpeg_stdout->start unless $w_ffmpeg_stdout->is_active;
        print STDERR '$w_ffmpeg_stdout->start'.$/;
    }
};


start_ffmpeg();

EV::loop;
