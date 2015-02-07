#!/usr/bin/perl -wT

use 5;
use strict;
use utf8;
use autodie;
use URI;
use Web::Scraper;
use Encode;
use JSON;
use Log::Log4perl;

our $VERSION = 1.0.1;

Log::Log4perl::init('/opt/meal-scraper/log.conf');
my $LOGGER = Log::Log4perl->get_logger('meal-scraper');

sub extract_meals {
	my %args = @_;
	my $meals = $args{meals};

	my @tmp = ();
	for (@{$meals}) {
		my $meal = {};
		my $row_meal_name = Encode::encode('utf8', $_);

		my @splitted = split /EUR/ms, $row_meal_name;
		if (@splitted != 2) {
			$LOGGER->error_die("Extract meals split broken while processing arg : $row_meal_name");
		}

		# Get meal name
		$meal->{'meal_name'} = cleanup_name(dirty_name => $splitted[0]);

		# Gxtract prices for meal
		my %prices = extract_prices(prices => $splitted[1]);
		$meal->{'price_student'} = $prices{'price_student'};
		$meal->{'price_price_employee'} = $prices{'price_employee'};
		$meal->{'price_guest'} = $prices{'price_guest'};
		push @tmp, $meal;
    }
    return @tmp;
}

sub cleanup_name {
	my %args = @_;
	my $dirty_name = $args{'dirty_name'};
	$dirty_name =~ s/^\s+|[\s\d]+$//gms;
	return $dirty_name;
}

sub extract_prices {
	my %args = @_;
	my $prices = $args{'prices'};
	my @extracted_prices = $prices =~ /(\d{1,2}[.]\d{1,2})/gms;

	my $NUM_PRICE_GROUPS = 3;
	if (@extracted_prices != $NUM_PRICE_GROUPS) {
		$LOGGER->error_die("Extract prices broken while processing arg : $prices");
	}

	return (
		price_student => $extracted_prices[0],
		price_employee => $extracted_prices[1],
		price_guest => $extracted_prices[2]
	);
}

my $day_dates = scraper {
	# scrap dates
	process 'tr.mensa_week_head th.mensa_week_head_col',
		'dates[]' => [ 'TEXT', qr/(\d{2}[.]\d{2}[.]\d{4})/sm ];

	# scrap specials
	process 'td.special', 'specials[]' => scraper {
		process 'p.mensa_speise', 'meals[]' => 'TEXT';
	};

	# scrap foods
	process 'td.food', 'foods[]' => scraper {
		process 'p.mensa_speise', 'meals[]' => 'TEXT';
	};

	# scrap side_dishes
	process 'td.side_dishes', 'side_dishes[]' => scraper {
		process 'p.mensa_speise', 'meals[]' => 'TEXT';
	};
};

my $URL_WEEK_MENU = 'http://www.studentenwerk-berlin.de/print/mensen/speiseplan/beuth/woche.html';
my $res = $day_dates->scrape(URI->new($URL_WEEK_MENU));

# Monday ... Friday => 5 dates 
my $BUSINESS_DAYS = 5;
if (@{$res->{'dates'}} != $BUSINESS_DAYS) {
	$LOGGER->error_die('Incorrect number of dates scraped. Expected 5 but was ' . scalar @{$res->{'dates'}});
}

my @week_meal_plan = ();

my $num_dates = @{$res->{'dates'}};
foreach my $i (0..$num_dates) {
	my $tmp = {};
	$tmp->{'date'} = $res->{'dates'}[$i];
	$tmp->{'specials'} = [ extract_meals(meals => \@{${$res->{'specials'}}[$i]{'meals'}}) ];
	$tmp->{'foods'} = [ extract_meals('meals' => \@{${$res->{'foods'}}[$i]{'meals'}}) ];
	$tmp->{'side_dishes'} = [ extract_meals('meals' => \@{${$res->{'side_dishes'}}[$i]{'meals'}}) ];
	push @week_meal_plan, $tmp;
}

# json processing
my $JSON = JSON->new->pretty(0);
my $json_week_menu = $JSON->encode(\@week_meal_plan);

# write json string to file
my $OUT_JSON_FILE = '/srv/perl/mensa_week_plan/week_menu.json';
open my $fh, '>', $OUT_JSON_FILE
	or $LOGGER->error_die("Could not open file : $OUT_JSON_FILE");
print {$fh} $json_week_menu;
close $fh;