package PDLNA::ContentItem;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010 Stefan Heumader <stefan@heumader.at>
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

use File::Basename;
use Date::Format;

use PDLNA::Utils;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{ID} = $$params{'id'};
	$self->{PATH} = $$params{'filename'};
	$self->{NAME} = basename($$params{'filename'});
	$self->{DATE} = $$params{'date'};
	$self->{SIZE} = $$params{'size'};

	bless($self, $class);
	return $self;
}

sub id
{
	my $self = shift;
	my $id = shift;

	$self->{ID} = $id if defined($id);
	return $self->{ID};
}

sub beautiful_id
{
	my $self = shift;
	return PDLNA::Utils::add_leading_char($self->{ID},3,'0');
}

sub name
{
	my $self = shift;
	return $self->{NAME};
}

sub date
{
	my $self = shift;
	return $self->{DATE};
}

sub size
{
	my $self = shift;
	return $self->{SIZE};
}

sub path
{
	my $self = shift;
	return $self->{PATH};
}

sub print_object
{
	my $self = shift;

	print "\t\t\tObject PDLNA::ContentItem\n";
	print "\t\t\t\tID:            ".PDLNA::Utils::add_leading_char($self->{ID},3,'0')."\n";
	print "\t\t\t\tFilename:      ".$self->{NAME}."\n";
	print "\t\t\t\tPath:          ".$self->{PATH}."\n";
	print "\t\t\t\tDate:          ".$self->{DATE}." (".time2str("%Y-%m-%d %H:%M", $self->{DATE}).")\n";
	print "\t\t\t\tSize:          ".$self->{SIZE}." Bytes\n";
}

1;
