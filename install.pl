#!/usr/bin/perl -w
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2011 Stefan Heumader <stefan@heumader.at>
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
	[ 'prefix|p:s', 'Prefix for installation path of libraries', { default => '/opt' }, ],
	[], # just an empty line for the usage message
	[ 'help|h', 'print usage method and exit' ],
);
print($usage->text), exit if $opt->help();

my $PREFIX = '.';
$PREFIX = $opt->prefix() if (defined($opt->prefix()));
$PREFIX .= '/' unless $PREFIX =~ /\/$/;

use Test::More;

print "------------------------------------------------------\n";
print "Step 1:\n";
print "Testing for necessary Perl Modules ...\n";
print "------------------------------------------------------\n";

use_ok ('Config');
use_ok ('Config::ApacheFormat');
use_ok ('Data::Dumper');
use_ok ('Date::Format');
use_ok ('Digest::SHA1');
use_ok ('Fcntl');
use_ok ('File::Basename');
use_ok ('File::Glob');
use_ok ('File::MimeInfo');
use_ok ('GD');
use_ok ('Getopt::Long::Descriptive');
use_ok ('Image::Info');
use_ok ('IO::Interface');
use_ok ('IO::Select');
use_ok ('IO::Socket');
use_ok ('IO::Socket::INET');
use_ok ('IO::Socket::Multicast');
use_ok ('LWP::UserAgent');
use_ok ('MP3::Info');
use_ok ('Net::IP');
use_ok ('Net::Netmask');
use_ok ('Movie::Info');
use_ok ('POSIX');
use_ok ('Socket');
use_ok ('Sys::Hostname');
use_ok ('threads');
use_ok ('threads::shared');
use_ok ('XML::Simple');

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

my %installation_files = (
	'rc.pDLNA' => ['f', '/etc/init.d/', 0755],
	'pDLNA.pl' => ['f', $PREFIX, 0755],
	'pdlna.conf' => ['f', '/etc/', 0644],
	'PDLNA' => ['d', $PREFIX, 0755],
	'README' => ['f', $PREFIX.'PDLNA/', 0644],
	'LICENSE' => ['f', $PREFIX.'PDLNA/', 0644],
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

my $regex = '+BIN="./pDLNA.pl"+BIN="'.$PREFIX.'pDLNA.pl"';
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

use lib ($PREFIX);

use_ok ('PDLNA::Config');
use_ok ('PDLNA::Content');
use_ok ('PDLNA::ContentDirectory');
use_ok ('PDLNA::ContentGroup');
use_ok ('PDLNA::ContentItem');
use_ok ('PDLNA::ContentLibrary');
use_ok ('PDLNA::ContentType');
use_ok ('PDLNA::Daemon');
use_ok ('PDLNA::Device');
use_ok ('PDLNA::DeviceList');
use_ok ('PDLNA::HTTPServer');
use_ok ('PDLNA::HTTPXML');
use_ok ('PDLNA::Library');
use_ok ('PDLNA::Log');
use_ok ('PDLNA::SSDP');
use_ok ('PDLNA::Status');
use_ok ('PDLNA::Utils');

done_testing();
