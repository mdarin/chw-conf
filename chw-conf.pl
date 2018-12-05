#!/usr/bin/perl -w 
# You will need the following to work with
# SQLite3
#
#  $ perl -MCPAN -e shell   
#  cpan> install DBI        
#  cpan> install DBD::SQLite
#
# Reference
#  http://www.perl.com/pub/a/2004/09/12/embedded.html
use warnings;
use strict;
use DBI;
use File::Spec;

our $VERSION = 0.3.0; # хз, тут надо читать


# *
# *
# * /!\ надо заменить русские буквы на латинские!!! [ГОТОВО] для начала сойдёт :)
# *
# *
my $dbh = DBI->connect( "dbi:SQLite:stk3.s3db" ) 
	or die "Cannot connect: $DBI::errstr";


my $query = q(SELECT name 
	FROM sqlite_master 
	WHERE type='table' 
	ORDER BY name;);

# ------------------------------------------------------------------------------
# получить список таблиц базы данных в sqlite
my $res = $dbh->selectall_arrayref($query);
print ":: Database \$dbname has got following tables:\n";
foreach (@$res) {
	print " * [@$_]\n";
#  Note $_->[0] is the same as $$_[0]
}
# ------------------------------------------------------------------------------

#
# Select complex name
#

$query = q(select name_complex
	from complexes;);

$res = $dbh->selectall_arrayref($query);
#foreach (@$res) {
#	print "@$_\n"
#		if @$_;
#}

my $complex = $res->[0][0];#"15k703M";
my $path = File::Spec->catfile("complex", $complex);

#
# Collect imitators
#
$query = q(select s.[name_stoika]
from stoika s 
order by s.[name_stoika];);

$res = $dbh->selectall_arrayref($query);
my $imitators = [()];
foreach (@$res) {
	my $imitator = $_->[0];
	push (@$imitators, $imitator);
}

#
# выкинуть не нужные названия (Это надо сделать в базе)
# в функцию вынести, просится кусок
my $new_imitators = [()];
foreach my $im (0..@$imitators) {
	my $imitator = $imitators->[$im];
	next unless $imitator;
	if ($imitator =~ m/.+?\-[12]\.\d+.*/) {
		push (@$new_imitators, $imitator);
		next;
	}
	my($cur, $other1) = $imitator =~ m/(.+?\-\d+)(\.\d+.*)/;
	next unless $imitators->[$im+1];
	my($next, $other2) = $imitators->[$im+1] =~ m/(.+?\-\d+)(\.\d+.*)/;
	shift (@$imitators) if ($cur eq $next);
	push (@$new_imitators, $cur);
}
print "@$new_imitators\n";
$imitators = $new_imitators;

#
# создать файл конфигурации аппаратуры сопряжения комплекса hardware.xml
#

$query = q(SELECT ct.[type_controller], c.[address], c.[ip_kis], c.[device_sopryazheniya], s.[name_stoika]
from controllers c, controllers_type ct, control ctl, indicators i, panels p, stoika s
where c.contr_type_id = ct.id
and c.id = ctl.[controller_id]
and ctl.[panel_id] = p.[id]
and p.[stoika_id] = s.[id]
group by c.[ip_kis]
order by c.[ip_kis];);

$res = $dbh->selectall_arrayref($query);
my $cmx_tpl = "<complex id=\"$complex\">";
my $dev_tpl = "<device type=\"%s\" id=\"%s%s\" address=\"%s\"> <!-- %s -->";
my $ctrl_tpl = "<controller type=\"%s\" address=\"0x%s\" />";
my $dev_rec = {
	'TYPE' => "",
	'ID' => "",
	'IP' => "",
	'IMITATOR' => "",
};


my $ctrl_rec = {
	'TYPE' => "",
	'ADDR'=> "",
};

@$dev_rec{ qw(TYPE ID IP) } = qw(kis 1 127.0.0.1 UNKNOWN IMITATOR);

if (3 != $res->[0][-2]) {
	$dev_rec->{'TYPE'} = "UNKNOWN DEVICE";
}

my $fname = "hardware.xml";
open my $hardware, ">$fname"
	or die "$0:Can't open $fname file: $!";

print $hardware "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print $hardware "<!-- WARNING! AUTOMATICALY GENERATED CODE\n";
print $hardware "     DO NOT MODIFY THE FILE MANUALY IF YOU\n";
print $hardware "     ARE DOUBTING WHAT ARE YOU REALY DO!\n";
print $hardware "     PROCESSOR VERSION 0.3-->\n";
printf $hardware "$cmx_tpl\n", $complex;


my $kis_ids = {};


# вывести список кис с адресами
$dev_rec->{'IP'} = $res->[0][2];
$dev_rec->{'IP'} =~ s/0(\d+)/$1/gi;
$dev_rec->{'IMITATOR'} = $res->[0][4];
printf $hardware "\t$dev_tpl\n", @$dev_rec{ qw(TYPE TYPE ID IP IMITATOR) };
$dev_rec->{'IP'} = $res->[0][2];
$kis_ids->{ $dev_rec->{'IMITATOR'} } = "$dev_rec->{'TYPE'}$dev_rec->{'ID'}";
foreach my $rec (@$res) {
	# закрыть предыдущий тег device и открыть новый
	if( $dev_rec->{'IP'} ne $rec->[2]) {
		print $hardware "\t</device>\n";
		$dev_rec->{'IP'} = $rec->[2];
		$dev_rec->{'IP'} =~ s/0(\d+)/$1/gi;
		$dev_rec->{'IMITATOR'} = $rec->[4];
		$dev_rec->{'ID'} ++;
		#my ($im, $other) = $dev_rec->{'IMITATOR'} =~ m/(15.+?\-.)(.+)/;
		#$kis_ids->{ $im } = "$dev_rec->{'TYPE'}$dev_rec->{'ID'}";
		$kis_ids->{ $dev_rec->{'IMITATOR'} } = "$dev_rec->{'TYPE'}$dev_rec->{'ID'}";
		printf $hardware "\t$dev_tpl\n", @$dev_rec{ qw(TYPE TYPE ID IP IMITATOR) };
	}
	# вывести список контроллеров для данного КИС
	@$ctrl_rec{ qw(TYPE ADDR) } = @$rec[0,1];
	$ctrl_rec->{'TYPE'} = &rus2lat ($ctrl_rec->{'TYPE'});
	printf $hardware "\t\t$ctrl_tpl\n", @$ctrl_rec{ qw(TYPE ADDR) };
}
print $hardware "\t</device>\n";
print $hardware "</complex>\n";

close $hardware;


#
# Отладочный код
#
while (my ($im, $kis_id) =each %$kis_ids) {
	print " :: DBG key: $im -> value: $kis_id\n";
}


#
# создать файлы событий для каждого имитатора комплекса controlevents.xml
#

# создать каталог для каждого имитатора и заполнить файл конфигураци перечнем ожидаемых событий
foreach my $im (@$imitators) {
	my $status = 'ok';
	my $name = $im;
	$name =~ s/K|К/k/i;
	$name =~ s/(703)/703M/;
	$name =~ s/\.|\-/_/g;
	#print "::$name $im\n";
	my $path = $name;
	unless (-e $path) {
		mkdir $path, oct "755"
			or warn "Can't create $path dir: $!";
	}

	#
	# выбрать данные в файл controlevents.xml для текущего имитатора
	#

	$path = File::Spec->catfile($path, "kis.xml");
		open my $kis, ">$path"
			or die "$0:Can't open $fname file: $!";

	print $kis "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
	print $kis "<!-- WARNING! AUTOMATICALY GENERATED CODE\n";
	print $kis "     DO NOT MODIFY THE FILE MANUALY IF YOU\n";
	print $kis "     ARE DOUBTING WHAT ARE YOU REALY DO!\n";
	print $kis "     PROCESSOR VERSION 0.3-->\n";
	print $kis "<kis>\n";

	print $kis "<!-- TODO:Допилить связь по kis id c hardware.xml -->\n";

	my $controller_tpl = "<controller %s=\"%s%s\" type=\"%s\" address=\"0x%s\" />";
	my $dev = {
		'TYPE' => "kis",
		'ID' => 1,
	};
	my $event_tpl = "<event ctype=\"%s\" index=\"%s\" code=\"0x%s\" domain=\"%s\" id=\"%s\" value=\"%s\" /> <!--[%s] [%s] [%s]-->";
	my $event_tpl_shot = "<event ctype=\"%s\" index=\"%s\" code=\"0x%s\" domain=\"%s\" id=\"%s\" value=\"%s\" />";
	my $ev = {
		'CTYPE' => "kis",
		'INDEX' => "0",
		'CODE' => "0",
		'DOMAIN' => "",
		'ID' => "",
		'VALUE' => "0",
		'COMMENT' => "",
		'NAME' => "",
		'PANEL' => "",
		'IMITATOR' => "",
	};

	#
	# связать контроллеры и имитаторы, выбрать конороллеры в разрезе имитаторов
	# выборку занести в файл kis.xml
	#

	print $kis "\t<controllers>\n";

	my $controller = {
		'TYPE' => "",
		'ADDR' => "",
		'IMITATOR' => "",
	};

	# TODO: [ГОТОВО] Средствами СУБД объедены два запроса через UNION
	# Тут надо бы собрать оба списка во едино, не доделал, доделать бы надо :)
	#

	$query = q(select ct.[type_controller], c.[address], s.[name_stoika]
	from controllers c, controllers_type ct, control cont, indicators i, panels p, stoika s
	where c.[contr_type_id] = ct.[id]
		and i.[controller_id] = c.[id] 
		and i.[panel_id] = p.[id]  
		and p.[stoika_id] = s.[id]  
		and s.[name_stoika] like '15_703_4%'
	union 
	select ct.[type_controller], c.[address], s.[name_stoika]
	from controllers c, controllers_type ct, control cont, indicators i, panels p, stoika s
	where c.[contr_type_id] = ct.[id]
		and cont.[controller_id] = c.[id] 
		and cont.[panel_id] = p.[id]  
		and p.[stoika_id] = s.[id]  
		and s.[name_stoika] like 'IMITATOR%');

	$query =~ s/IMITATOR/$im/gm;
	$res = $dbh->selectall_arrayref($query);

	#print " :: DBG im: $im\n";

	foreach my $rec (@$res) {
		$controller->{'TYPE'} = &rus2lat ($rec->[0]);
		@$controller{ qw(ADDR IMITATOR) } = @$rec[1,2];
		#print " :: DBG $controller->{'IMITATOR'}\n";
		#printf $kis "\t\t$controller_tpl\n", $dev->{'TYPE'}, $kis_ids->{ $controller->{'IMITATOR'} }, @$controller{ qw(TYPE ADDR) };
		#printf $kis "\t\t$controller_tpl\n", @$dev{ qw(TYPE) }, $kis_ids->{$im}, @$controller{ qw(TYPE ADDR) };
		printf $kis "\t\t$controller_tpl\n", @$dev{ qw(TYPE TYPE ID) }, @$controller{ qw(TYPE ADDR) };
	}

	print $kis "\t</controllers>\n";
	$dev->{'ID'} ++;

	#
	# выбрать события из БД и занести их в файл
	#

	$query = q(select cd.code, c.name_from_tb, c.naimenovanie, c.type, p.panel_name, ct.type_controller, ctl.address, s.name_stoika
from control c, control_code cd, controllers ctl, controllers_type ct, panels p, stoika s
where cd.managment_id = c.id
  and ctl.id = c.controller_id
  and ctl.contr_type_id = ct.id
  and c.panel_id = p.id
  and p.stoika_id = s.id
  and s.name_stoika like 'IMITATOR%';);

	$query =~ s/IMITATOR/$im/gm;

	$res = $dbh->selectall_arrayref($query);

	print $kis "\t<controlevents>\n";

	foreach my $rec (@$res) {
		# 0   1    2     3            4          5   6   7
		# E1 SA16 ОТМ Кнопка 15K703-4.01.00.120 ККД 41 15K703-4.01
		@$ev{ qw(CODE ID NAME COMMENT PANEL IMITATOR) } = @$rec[0..7];
		$ev->{'CTYPE'} = &rus2lat($rec->[5]);
		$ev->{'VALUE'} = "0";
		printf $kis "\t\t$event_tpl\n", @$ev{ qw(CTYPE INDEX CODE PANEL ID VALUE NAME COMMENT) }, $im;
		$ev->{'CODE'} = "80$ev->{'CODE'}";
		$ev->{'VALUE'} = "1";
		printf $kis "\t\t$event_tpl_shot\n", @$ev{ qw(CTYPE INDEX CODE PANEL ID VALUE) };
	}
	print $kis "\t</controlevents>\n";
	print $kis "</kis>\n";
	
	close $kis;
	my $spacing = 30;
	my $s = $spacing - length $im;
	print " * [$im]" . " " x $s . "[ $status ]\n";
}


# закрыть соединение с базой данных
$dbh->disconnect;
print "\n"x2;
#------------------------------------------------------------------------------
#
#
sub rus2lat {
	my $line = shift;
	# Это ваще лажа, но хоть как-то :)
	$line =~ s/К/K/gi;
	$line =~ s/Д/D/gi;
	$line =~ s/С/S/gi;
	$line =~ s/И/I/gi;
	$line =~ s/У/U/gi;
	$line =~ s/Т/T/gi;
	$line =~ s/В/V/gi;
	#...
	$line;
}
