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

alter table fenite_op add id varchar(100);
alter table fenite_op add type varchar(2);

create unique index idx_fenite_frases on fenite_frases (frase, type);
create unique index idx_fenite_regex on fenite_regex (regex);
create unique index idx_fenite_rep on fenite_rep (key);

create table fenite_firstname (
	id varchar(100),
	firstname varchar(100)
);

create unique index idx_fenite_firstname on fenite_firstname (id);

create table fenite_cooldown (
	chatid char(50) primary key
);

create table fenite_active (
	chatid char(50) not null,
	start int not null,
	end int not null
);
