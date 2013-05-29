#!/usr/bin/perl -w
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
	'%c %o ',
	[ 'prefix|p:s', 'define prefix for installation path of libraries', { default => '/opt' }, ],
	[ 'install|i', 'checks for necessary requirements and installs pDLNA' ],
	[ 'update|u', 'checks for necessary requirements and installs pDLNA (updating will be implemented later)' ],
	[ 'checkrequirements|c', 'checks for necessary requirements' ],
	[], # just an empty line for the usage message
	[ 'help|h', 'print usage method and exit' ],
);
print($usage->text), exit if $opt->help();

my $PREFIX = '/opt';
$PREFIX = $opt->prefix() if (defined($opt->prefix()));
$PREFIX .= '/' unless $PREFIX =~ /\/$/;

if (!$opt->checkrequirements() && !$opt->install() && !$opt->update())
{
	print($usage->text);
	exit;
}

use Test::More;

print "------------------------------------------------------\n";
print "Step 1:\n";
print "Testing for necessary Perl Modules ...\n";
print "------------------------------------------------------\n";


use_ok ('Config');
use_ok ('Config::ApacheFormat');
use_ok ('Data::Dumper');
use_ok ('Date::Format');
use_ok ('DBD::SQLite');
use_ok ('DBI');
use_ok ('Digest::MD5');
use_ok ('Digest::SHA1');
use_ok ('Fcntl');
use_ok ('File::Basename');
use_ok ('File::Glob');
use_ok ('File::MimeInfo');
use_ok ('GD');
use_ok ('GD::Graph::area');
use_ok ('Getopt::Long::Descriptive');
use_ok ('Image::Info');
use_ok ('IO::Interface');
use_ok ('IO::Select');
use_ok ('IO::Socket');
use_ok ('IO::Socket::INET');
use_ok ('IO::Socket::Multicast');
use_ok ('LWP::UserAgent');
use_ok ('Net::Address::Ethernet');
use_ok ('Net::Interface');
use_ok ('Net::IP');
use_ok ('Movie::Info');
use_ok ('POSIX');
use_ok ('Proc::ProcessTable');
use_ok ('SOAP::Lite');
use_ok ('Socket');
use_ok ('Sys::Hostname');
use_ok ('Sys::Syslog');
use_ok ('threads');
use_ok ('threads::shared');
use_ok ('Time::HiRes');
use_ok ('URI::Split');
use_ok ('XML::Simple');

if (!$opt->install() && !$opt->update())
{
	done_testing();
	exit;
}

print "------------------------------------------------------\n";
print "Step 2:\n";
print "Testing for necessary Perl Modules for installation ...\n";
print "------------------------------------------------------\n";

use_ok ('File::Copy');
use_ok ('File::Copy::Recursive');

print "------------------------------------------------------\n";
print "Step 3:\n";
print "Installing files ...\n";
print "------------------------------------------------------\n";

use File::Copy::Recursive qw(rcopy);

$PREFIX .= 'pDLNA/';
unless (-d $PREFIX)
{
	mkdir($PREFIX, 0755);
}

my %installation_files = (
	'rc.pDLNA' => ['f', '/etc/init.d/', 0755],
	'pDLNA.pl' => ['f', $PREFIX, 0755],
	'pdlna.conf' => ['f', '/etc/', 0644],
	'PDLNA' => ['d', $PREFIX, 0755],
	'external_programs' => ['d', $PREFIX, 0755],
	'README' => ['f', $PREFIX, 0644],
	'LICENSE' => ['f', $PREFIX, 0644],
	'VERSION' => ['f', $PREFIX, 0644],
);

foreach my $key (keys %installation_files)
{
	if (-d $installation_files{$key}->[1])
	{
		if ($installation_files{$key}->[0] eq 'f' || $installation_files{$key}->[0] eq 'd')
		{
			if (rcopy('./'.$key, $installation_files{$key}->[1].$key))
			{
				pass("Installed './$key' to '$installation_files{$key}->[1]$key'.");
				if (chmod($installation_files{$key}->[2], $installation_files{$key}->[1].$key))
				{
					pass("Set rights for '$installation_files{$key}->[1]$key'.");
				}
				else
				{
					fail("Unable to set rights for '$installation_files{$key}->[1]$key': $!");
				}
			}
			else
			{
				fail("Unable to install './$key' to '$installation_files{$key}->[1]$key': $!");
			}
		}
		else
		{
			fail("Unknown filetype for file named '$key'.");
		}
	}
	else
	{
		fail("$installation_files{$key}->[1] is NOT existing. Unable to install necessary files.");
	}
}

print "------------------------------------------------------\n";
print "Step 4:\n";
print "Setting of relevant paths ...\n";
print "------------------------------------------------------\n";

my $regex = '+DIR="./"+DIR="'.$PREFIX.'"';
if (system("sed -i -e s'$regex'+ /etc/init.d/rc.pDLNA") == 0)
{
	pass("Changed path for binary in '/etc/init.d/rc.pDLNA'.");
}
else
{
	fail("Failed to change path for binary in '/etc/init.d/rc.pDLNA': $!.");
}

$regex = "+use lib ('./');+use lib ('/opt');+";
if (system('sed -i -e s"'.$regex.'" '.$PREFIX.'pDLNA.pl') == 0)
{
	pass("Changed path for lib in '".$PREFIX."pDLNA.pl'.");
}
else
{
	fail("Failed to change path for lib in '".$PREFIX."pDLNA.pl': $!.");
}

print "------------------------------------------------------\n";
print "Step 5:\n";
print "Checking for pDLNA Perl Modules ...\n";
print "------------------------------------------------------\n";

# delete local directory from PATH
for (my $i = 0; $i < @INC; $i++)
{
	splice(@INC, $i, 1) if $INC[$i] eq '.';
}
push(@INC, $PREFIX); # push the new LIB directory to PATH

use_ok ('PDLNA::Config');
use_ok ('PDLNA::ContentLibrary');
use_ok ('PDLNA::Daemon');
use_ok ('PDLNA::Database');
use_ok ('PDLNA::Devices');
use_ok ('PDLNA::HTTPServer');
use_ok ('PDLNA::HTTPXML');
use_ok ('PDLNA::Log');
use_ok ('PDLNA::Media');
use_ok ('PDLNA::SOAPClient');
use_ok ('PDLNA::SOAPMessages');
use_ok ('PDLNA::SpecificViews');
use_ok ('PDLNA::SSDP');
use_ok ('PDLNA::Statistics');
use_ok ('PDLNA::Status');
use_ok ('PDLNA::Transcode');
use_ok ('PDLNA::Utils');
use_ok ('PDLNA::WebUI');

done_testing();
