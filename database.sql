create table fenite_frases (
	frase text not null, 
	type varchar(20)
);

create table fenite_molestar (
	codename char(100) not null
);

create table fenite_op (
	codename char(100) not null
);

create table fenite_mmg (
	chatid char(50) not null,
	codename char(100) not null,
	count int not null,
	year char(4), 
	id varchar(100), 
	firstname varchar(100), 
	chat varchar(100)
);

create table fenite_regex (
	regex text not null
);

create table fenite_rep (
	key char(200) not null,
	frase text not null,
	type char(50) not null
);