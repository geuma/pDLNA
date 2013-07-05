package LDLNA::SpecificViews;
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

use LDLNA::Database;
use LDLNA::Utils;
use LDLNA::Config;

our %SPECIFICVIEWS = (
	'A' =>  {
		'MediaType' => 'audio',
		'GroupType' => {
			'F' => 'folder',
		},
	},
	'I' =>  {
		'MediaType' => 'image',
		'GroupType' => {
			'F' => 'folder',
		},
	},
	'V' =>  {
		'MediaType' => 'video',
		'GroupType' => {
			'D' => 'folder',
		},
	},
);

our %SPECIFICVIEW_QUERIES = (
	'folder' => {
		'group_amount' => 'SELECT COUNT("ID") AS "AMOUNT" FROM "DIRECTORIES" WHERE "PATH" IN ( SELECT "PATH" FROM "FILES" WHERE "TYPE" = ? )',
		'group_elements' => 'SELECT "ID", "NAME", "PATH" FROM "DIRECTORIES" WHERE "PATH" IN ( SELECT "PATH" FROM "FILES" WHERE "TYPE" = ? ) ORDER BY "NAME"',
		'item_amount' => 'SELECT COUNT("ID") AS "AMOUNT" FROM "FILES" WHERE "PATH" IN ( SELECT "PATH" FROM "DIRECTORIES" WHERE "ID" = ? ) AND "TYPE" = ?',
		'item_elements' => 'SELECT "ID" FROM "FILES" WHERE "PATH" IN ( SELECT "PATH" FROM "DIRECTORIES" WHERE "ID" = ? ) AND "TYPE" = ?',
	},
);

sub supported_request
{
	my $media_type = shift;
	my $group_type = shift;

	if (defined($SPECIFICVIEWS{$media_type}) && defined($SPECIFICVIEWS{$media_type}->{'GroupType'}->{$group_type}))
	{
		return 1;
	}
	return 0;
}

sub get_groups
{
	my $media_type = shift;
	my $group_type = shift;
	my $starting_index = shift;
	my $requested_count = shift;
	my $group_elements = shift;


    my $dbh = LDLNA::Database::connect();
	my $sql_query = $SPECIFICVIEW_QUERIES{$SPECIFICVIEWS{$media_type}->{'GroupType'}->{$group_type}}->{'group_elements'};
    if (defined($starting_index) && defined($requested_count))
	{
		if ($CONFIG{DB_TYPE} eq "PGSQL") 
        {
         $sql_query .= ' OFFSET '.$starting_index.' LIMIT '.$requested_count;
        
        }
        else
        {
		  $sql_query .= ' LIMIT '.$starting_index.', '.$requested_count;
        }
	
	}

	LDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => [ $SPECIFICVIEWS{$media_type}->{'MediaType'}, ],
		},
		$group_elements,
	);
	LDLNA::Database::disconnect($dbh);
}

sub get_amount_of_groups
{
	my $media_type = shift;
	my $group_type = shift;

        my $dbh = LDLNA::Database::connect();
        my @group_amount = ();
        LDLNA::Database::select_db(
		$dbh,
		{
			'query' => $SPECIFICVIEW_QUERIES{$SPECIFICVIEWS{$media_type}->{'GroupType'}->{$group_type}}->{'group_amount'},
			'parameters' => [ $SPECIFICVIEWS{$media_type}->{'MediaType'}, ],
		},
		\@group_amount,
        );

        LDLNA::Database::disconnect($dbh);
	return $group_amount[0]->{AMOUNT};
}

sub get_items
{
	my $media_type = shift;
	my $group_type = shift;
	my $group_id = shift;
	my $starting_index = shift;
	my $requested_count = shift;
	my $item_elements = shift;

        my $dbh = LDLNA::Database::connect();
	my $sql_query = $SPECIFICVIEW_QUERIES{$SPECIFICVIEWS{$media_type}->{'GroupType'}->{$group_type}}->{'item_elements'};
    if (defined($starting_index) && defined($requested_count))
	{
        if ($CONFIG{DB_TYPE} eq "PGSQL") 
        {
         $sql_query .= ' OFFSET '.$starting_index.' LIMIT '.$requested_count;
        
        }
        else
        {
		  $sql_query .= ' LIMIT '.$starting_index.', '.$requested_count;
        }
	}

	LDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => [ $group_id, $SPECIFICVIEWS{$media_type}->{'MediaType'}, ],
		},
		$item_elements,
	);
        LDLNA::Database::disconnect($dbh);
         
}

sub get_amount_of_items
{
	my $media_type = shift;
	my $group_type = shift;
	my $group_id = shift;

        my @item_amount = ();
        my $dbh = LDLNA::Database::connect();
	LDLNA::Database::select_db(
		$dbh,
		{
			'query' => $SPECIFICVIEW_QUERIES{$SPECIFICVIEWS{$media_type}->{'GroupType'}->{$group_type}}->{'item_amount'},
			'parameters' => [ $group_id, $SPECIFICVIEWS{$media_type}->{'MediaType'}, ],
		},
		\@item_amount,
	);
        LDLNA::Database::disconnect($dbh);
	return $item_amount[0]->{AMOUNT};
}

1;
