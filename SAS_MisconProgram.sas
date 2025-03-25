libname reneephi '/sasdata'; 

/*only need to do this the first time*/
proc sql;
drop table reneephi.Z_MisconductDATA;
create table reneephi.Z_MisconductDATA as (
select *
from work.MisconductDATA
);
run;

proc sql;
drop table reneephi.Z_misconbegin;
create table reneephi.Z_misconbegin as (
select *
     ,(case 
	    when result_oic_offence_code = '1' then charged_oic_offence_code 
		else result_oic_offence_code
	   end) as offen_code
     ,(case 
	    when cont_desc like '%85%' then 'Y'
		else 'N'
	   end) as eightyfivepercent
	 ,left(put(doc_num,6.)) as doc_num_var
	 ,(case  
	    when adjust_days=. then 0
		when adjust_days<>. then adjust_days
	  end) as adjust_days_new
from reneephi.Z_MisconductDATA
/*WHERE (prison_exit_date BETWEEN '01jan2013'd AND '31dec2013'd)*/
);
run;

/*base table with stage 1 re-codes*/
/*recodes:  total terms a group category/days/months, total days served, and days served before misconduct*/
proc sql; 
drop table reneephi.Z_misconb1;
create table reneephi.Z_misconb1 as (
select m.*
      ,(case 
        when total_term = 0 then 0
	    when total_term >0   and total_term  < 5.0000001 then 5
        when total_term >=5  and total_term < 10.0000001 then 10 
		when total_term >=10 and total_term < 15.0000001 then 15
		when total_term >=15 and total_term < 20.0000001 then 20
		when total_term >=20 and total_term < 25.0000001 then 25
		when total_term >=25 and total_term < 30.0000001 then 30
		when total_term >=30 and total_term < 35.0000001 then 35
		when total_term >=35 and total_term < 40.0000001 then 40
		when total_term >=40 and total_term < 45.0000001 then 45
	   else 99999
	   end) as total_termyr_gp
	  ,(total_term*365.25) as total_term_days
	  ,(total_term*30.42) as total_term_mths
	  ,(prison_exit_date - prison_admit_date) as total_days_served
	  ,(offence_date - prison_admit_date) as tot_days_bf_miscon
	  ,(case  
	    when SENTENCE_ADJUST_CODE in ('B2') then 45
		when SENTENCE_ADJUST_CODE in ('1B') then 60
		when SENTENCE_ADJUST_CODE in ('2A') then 120
		when SENTENCE_ADJUST_CODE in ('A2') then 180
		when SENTENCE_ADJUST_CODE in ('2X','X2','6X','X6') then 365
		else 0
		end) as max_penalty
	  ,(case
	    when oic_offence_category = 'A' and sentence_adjust_code in ('2X','X2')      then 'X'
		when oic_offence_category = 'A' and sentence_adjust_code in ('1B','B2')      then 'B'
		when oic_offence_category = 'B' and sentence_adjust_code in ('2A','A2')      then 'A'
		when oic_offence_category = 'B' and sentence_adjust_code in ('2X','X2','X6') then 'X'
		when oic_offence_category = 'X' and sentence_adjust_code in ('A2','2A')      then 'A'
		when oic_offence_category = 'X' and sentence_adjust_code in ('1B')           then 'B'
		else oic_offence_category
		end) as miscon_class
from reneephi.Z_misconbegin m)
;
run; 


/*adding additional fields that could not be created in stage 1*/
/*this includes:  percent of time served, flag if any days to take, flag if can take max days, flag if days were actually removed*/
proc sql;
drop table reneephi.Z_misconc1;
create table reneephi.Z_misconc1 as ( 
select m.*
      ,(case when total_term < 99999 then (total_days_served/total_term_days)
         when total_term >= 99999 then 99999
	     else .
        end) as pct_served
	  ,(case
	    when NET_CREDITS >= max_penalty then 'Y'
		when net_credits < max_penalty then 'N'
		end) as sufficient_days
	  ,max_penalty - adjust_days_new as max_penalty_diff
	  ,(case
	    when net_credits > 0 then 'Y'
		when net_credits <=0 then 'N'
		end) as Days_To_Take
	  ,(case 
         when adjust_days_new > 0 then 'Y'
         else 'N'
        end) as days_removed
	  ,(row_id-1) as prior_infrac_test
	  ,(tot_days_bf_miscon/total_term_days) as pct_served_upto_miscon
from reneephi.Z_misconb1 m
)
;
run; 

/*adding additional fields that could not be created in stage 1 or 2*/
/*this includes:  percent of time served as a group, what the penalty status was, and if sanctioned to a day loss*/
/*null cases should be:  life sentences/delincar, errant sentences (i.e., missing data) =39/252*/
proc sql;
drop table reneephi.Z_Miscon_final1;
create table reneephi.Z_Miscon_final1 as ( 
select m.*
      ,(case 
        when total_term < 99999 and pct_served = 0 then 0
		when total_term < 99999 and pct_served > 0 and pct_served <.10000001 then 10
        when total_term < 99999 and pct_served > .1 and pct_served <.20000001 then 20
		when total_term < 99999 and pct_served > .2 and pct_served <.30000001 then 30
        when total_term < 99999 and pct_served > .3 and pct_served <.40000001 then 40
		when total_term < 99999 and pct_served > .4 and pct_served <.50000001 then 50
        when total_term < 99999 and pct_served > .5 and pct_served <.60000001 then 60
		when total_term < 99999 and pct_served > .6 and pct_served <.70000001 then 70
		when total_term < 99999 and pct_served > .7 and pct_served <.80000001 then 80
        when total_term < 99999 and pct_served > .8 and pct_served <.90000001 then 90
		when total_term < 99999 and pct_served > .9 and pct_served <.99999999 then 99
		when total_term < 99999 and pct_served >= 1 then 100
		else .
		end) as pct_served_gp
	  ,(case
	    when adjust_days_new is not null and net_credits - adjust_days >0  and max_penalty_diff > 0 then 'MoreDaysToTake'
		when adjust_days_new is not null and net_credits - adjust_days >0  and max_penalty_diff <=0 then 'MaxedOutPenalty'
		when adjust_days_new is not null and net_credits - adjust_days <=0 and max_penalty_diff <=0 then 'MaxedOutPenalty'
		when adjust_days_new is not null and net_credits - max_penalty <=0 then 'NotEnoughCredits'
        else 'NotSanctionDayLoss'
        end) as Penalty_Status
      ,(case  
	    when Days_To_Take = 'Y' and days_removed = 'Y' then 1
		when Days_To_Take = 'Y' and days_removed = 'N' then 0
		end) as daysanct  /*created this for RQ2-days removed yes or no, but only applicable to those who had days to take*/
	  ,(case when max_penalty_diff  < 0 then max_penalty
	    else adjust_days_new
		end) as adjust_days_rc  /*recoding this since some inmates were deducted more credits than infraction allowed (e.g., B=60 but removed 150)*/ /*I DO MORE BELOW*/
      ,(case 
         when offen_code in ('202','217','218','223','903','908') then 'Drugs'
         when offen_code in ('209','1601','1602','1603','1604','1605','1606','1607','302','309') then 'Escape'
         when offen_code in ('222','1201','1202','1203','1701','306') then 'Failure to Comply'
		 when offen_code in ('910','1401','1402') then 'Gambling'
         when offen_code in ('101','102','103','105','201','203','204','210','213','214','215','216','219','220','221','225','228','229','232','301','303','304','305','601','901','904','905','906','907','909','911','912','913','1101','1301','1302','1303','1501','1502','1503','212','226','227','307','805') then 'Other Non-Violent'
		 when offen_code in ('104','801','802','803','804','1102','1103') then 'Other Violent'
		 when offen_code in ('1001','1003') then 'Sexual Activity'
		 when offen_code in ('211') then 'Tattoo'
		 when offen_code in ('701','702','703','704') then 'Theft'
		 when offen_code in ('224','401','402','403','404','405','406','407','408','409','502','503','504','505','1002','1004','501') then 'Threats or Battery'
		 when offen_code in ('230','231','235','236') then 'Tobacco'
		 when offen_code in ('205','206','207','208','233','234','227N') then 'Unauthorized Communications'
		 when offen_code in ('902') then 'Weapons'
         else offen_code
        end) as miscon_type_detail
      ,(case 
         when offen_code in ('101','102','103','105','201','203','204','210','213','214','215','216','219','220','221','225','228','229','232','301','303','304','305','601','801','802','803','804','901','904','905','906','907','909','911','912','913','1101','1301','1302','1303','1501','1502','1503','212','226','227','307','805','910','1401','1402','1001','1003','205','206','207','208','1604','1605','1606','1607','302','309','222','1201','1202','1203','1701','306','211','202','217','218','223','903','908','209','1601','1602','1603','233','234','227N','701','702','703','704','230','231','235','236') then 'Non-Violent'
		 when offen_code in ('104','1102','1103','902','224','401','402','403','404','405','406','407','408','409','502','503','504','505','1002','1004','501') then 'Violent'
         else offen_code
        end) as miscon_type
	  ,(case
	     when prior_infrac_test =0 then 'N'
		 when prior_infrac_test<>0 then 'Y'
		end) as prior_infractions
      ,(case
         when MR_MHL = 'O'  then 0
         when MR_MHL = 'A'  then 1	
		 when MR_MHL = 'B'  then 2
		 when MR_MHL = 'C1' then 3
		 when MR_MHL = 'C2' then 3
		 when MR_MHL = 'D'  then 4
		 else .
		 end) as mhl
      ,(case
         when LAST_MHL = 'O'  then 0
         when LAST_MHL = 'A'  then 1	
		 when LAST_MHL = 'B'  then 2
		 when LAST_MHL = 'C1' then 3
		 when LAST_MHL = 'C2' then 3
		 when LAST_MHL = 'D'  then 4
		 else .
		 end) as exit_mhl
	   ,(case
	      when m_facname is null then 'LAWTON CORRECTIONAL FACILITY'
		  else m_facname
		 end) as facname
	   ,(case
	      when m_factype is null then 'Private Prison'
		  else m_factype
		 end) as factype
	   ,(case
	      when m_factype in ('Community Corr. Center','Comm. Work Center','Halfway Houses','Global Positioning System','Electronic Monitoring Program') then 'MIN'
		  when m_facname in ('CHARLES E. BILL JOHNSON CORR. CENTER','DR. EDDIE WARRIOR CORRECTIONAL CENTER','HOWARD MCLEOD CORRECTIONAL CENTER'
                            ,'JACKIE BRANNON CORRECTIONAL CENTER','JESS DUNN CORRECTIONAL CENTER','JIM E HAMILTON CORRECTIONAL CENTER','JOHN LILLEY CORRECTIONAL CENTER'
                            ,'NORTHEAST OKLAHOMA CORR. CENTER','WILLIAM S. KEY CORRECTIONAL CENTER','ADAIR COUNTY JAIL','CHOCTAW COUNTY JAIL','CRAIG COUNTY JAIL'
                            ,'CREEK COUNTY JAIL','JEFFERSON COUNTY JAIL','LEFLORE COUNTY JAIL','NOWATA COUNTY JAIL','OKMULGEE COUNTY JAIL','OTTAWA COUNTY JAIL'
                            ,'PUSHMATAHA COUNTY JAIL','SEQUOYAH COUNTY JAIL') then 'MIN'
		  when m_factype = 'Private Prison' then 'MED'
          when m_facname is null then 'MED'
          when m_facname in ('JAMES CRABTREE CORRECTIONAL CENTER','JOSEPH HARP CORRECTIONAL CENTER','LEXINGTON CORRECTIONAL CENTER','MABEL BASSETT CORRECTIONAL CENTER'
                             ,'MACK ALFORD CORRECTIONAL CENTER','OKLAHOMA STATE REFORMATORY','R.B. DICK CONNER CORRECTIONAL CENTER','COMANCHE COUNTY JAIL','COTTON COUNTY JAIL'
                             ,'MAJOR COUNTY JAIL','MARSHALL COUNTY JAIL','OKLAHOMA COUNTY JAIL','ROGER MILLS COUNTY JAIL','TILLMAN COUNTY JAIL') then 'MED'
		  when m_facname in ('LEX ASSESSMENT & RECEPTION CENTER','MABEL BASSETT ASSESSMENT & RECEPTION CEN','OKLAHOMA STATE PENITENTIARY') then 'MAX'
          else m_factype
		 end) as security
	   ,(case
	      when m_factype in ('Community Corr. Center','Comm. Work Center','Halfway Houses','Global Positioning System','Electronic Monitoring Program') then 'COMM'
		  when m_facname in ('CHARLES E. BILL JOHNSON CORR. CENTER','DR. EDDIE WARRIOR CORRECTIONAL CENTER','HOWARD MCLEOD CORRECTIONAL CENTER'
                            ,'JACKIE BRANNON CORRECTIONAL CENTER','JESS DUNN CORRECTIONAL CENTER','JIM E HAMILTON CORRECTIONAL CENTER','JOHN LILLEY CORRECTIONAL CENTER'
                            ,'NORTHEAST OKLAHOMA CORR. CENTER','WILLIAM S. KEY CORRECTIONAL CENTER','ADAIR COUNTY JAIL','CHOCTAW COUNTY JAIL','CRAIG COUNTY JAIL'
                            ,'CREEK COUNTY JAIL','JEFFERSON COUNTY JAIL','LEFLORE COUNTY JAIL','NOWATA COUNTY JAIL','OKMULGEE COUNTY JAIL','OTTAWA COUNTY JAIL'
                            ,'PUSHMATAHA COUNTY JAIL','SEQUOYAH COUNTY JAIL') then 'MIN'
		  when m_factype = 'Private Prison' then 'MAX/MED'
          when m_facname is null then 'MAX/MED'
          when m_facname in ('JAMES CRABTREE CORRECTIONAL CENTER','JOSEPH HARP CORRECTIONAL CENTER','LEXINGTON CORRECTIONAL CENTER','MABEL BASSETT CORRECTIONAL CENTER'
                             ,'MACK ALFORD CORRECTIONAL CENTER','OKLAHOMA STATE REFORMATORY','R.B. DICK CONNER CORRECTIONAL CENTER','COMANCHE COUNTY JAIL','COTTON COUNTY JAIL'
                             ,'MAJOR COUNTY JAIL','MARSHALL COUNTY JAIL','OKLAHOMA COUNTY JAIL','ROGER MILLS COUNTY JAIL','TILLMAN COUNTY JAIL') then 'MAX/MED'
		  when m_facname in ('LEX ASSESSMENT & RECEPTION CENTER','MABEL BASSETT ASSESSMENT & RECEPTION CEN','OKLAHOMA STATE PENITENTIARY') then 'MAX/MED'
          else m_factype
		 end) as security_rc
		,(case
		   when days_between_miscon is not null then days_between_miscon
		   when days_between_miscon is null then (offence_date - prison_admit_date)
		  end) as days_to_miscon
		,(case
		   when a_lsi_totalscore is not null then a_lsi_totalscore
		   when a_lsi_totalscore is null then 29.41643
          end) as lsi_score
from reneephi.Z_misconc1 m)
;
run; 


/********MENTAL HEALTH LEVEL********/
/*AGGREGATING MOST SEVERE MHL ON FILE TO INMATE LEVEL SINCE SO MANY MISSING AT INFRACTION LEVEL*/
proc sql;
drop table reneephi.Z_mhl;
create table reneephi.Z_mhl as (
select distinct doc_num, max(mhl) as mhl_cat
from reneephi.Z_Miscon_final1
group by doc_num
);
run;

/*JOINING AGG. MHL w/  REST OF DATA*/
proc sql;
drop table reneephi.Z_mhl_finaljoin;
create table reneephi.Z_mhl_finaljoin as (
select f.*, m.mhl_cat 
from reneephi.Z_Miscon_final1 f
inner join reneephi.Z_mhl m
on f.doc_num = m.doc_num)
;
run;


/********MULTIPLE VIOLATIONS********/
/*redoing code to identify cases with multiple infractions on one date*/
/*first step -find dates where there are no days between infractions*/
/*working from prior joined table (mhl) and then will again join with what i call final table*/
proc sql;
drop table reneephi.Z_multiple_infrac_date;
create table reneephi.Z_multiple_infrac_date as
(select distinct doc_num, offence_date
from reneephi.Z_mhl_finaljoin
where days_to_miscon = 0
group by doc_num, offence_date);
run;

/*second step-link this date with no days between infractions up with other dates so that i can flag as having multiple infractions*/
proc sql;
drop table reneephi.Z_multiple_infractions_join;
create table reneephi.Z_multiple_infractions_join as
(select distinct m.*
       ,(case
         when m.days_to_miscon=0 and m.row_id-1=1 then 'N'
	     when m.row_id=1 then 'N'
	     else 'Y'
         end) as priors
		,(case 
		   when m.offence_date = j.offence_date then 1
		   else 0
		  end) as multiple_miscon
from reneephi.Z_mhl_finaljoin m
left join reneephi.Z_multiple_infrac_date j
on m.doc_num=j.doc_num
and m.offence_date=j.offence_date
);
run;


/*third step for creating a calculation to allow me to more accurately identify priors - here: am counting row differences in days to miscon, looking for 0s*/
proc sql;
drop table reneephi.Z_multiple_infractions_2;
create table reneephi.Z_multiple_infractions_2 as 
(select b.*
      ,(SELECT MAX(days_to_miscon) 
        FROM reneephi.Z_multiple_infractions_join 
        WHERE days_to_miscon < b.days_to_miscon),days_To_miscon AS diff
from reneephi.Z_multiple_infractions_join b);
run;

/********PRIOR VIOLATIONS********/
/*finding minimum offense date to use as a paramter to identify when something is prior and when it isn't:  this is a multi-part identification*/
proc sql;
drop table reneephi.Z_min_off_date;
create table reneephi.Z_min_off_date as (
select distinct doc_num, min(offence_date) as date
from reneephi.Z_multiple_infractions_2 b
group by doc_num);
run;

/*joining the minimum offence date to the larger table:  essentially aggregating it up*/
proc sql;
drop table reneephi.Z_multiple_infractions_final;
create table reneephi.Z_multiple_infractions_final as
(select m.*, j.date, (m.offence_date-j.date) as diff2
from reneephi.Z_multiple_infractions_2 m
left join reneephi.Z_min_off_date j
on m.doc_num=j.doc_num
);
run;



/*days between*/
proc sql;
drop table reneephi.Z_days_to_miscon;
create table reneephi.Z_days_to_miscon as
(select distinct doc_num, offence_date, max(days_to_miscon) as days
from reneephi.Z_multiple_infractions_final
group by doc_num, offence_date);
run;

/*joining the minimum offence date to the larger table:  essentially aggregating it up*/
proc sql;
drop table reneephi.z_days_to_miscon_final;
create table reneephi.z_days_to_miscon_final as
(select m.*
       ,(case 
	      when m.miscon_class = 'B' then 1
		  when m.miscon_class = 'A' then 2
		  when m.miscon_class = 'X' then 3
		 end) as level
       ,j.days
from reneephi.Z_multiple_infractions_final m
left join reneephi.Z_days_to_miscon j
on m.doc_num=j.doc_num
and m.offence_date=j.offence_date
);
run;






/*--sample size:  moved from above-this is the number before cases removed*/
/*CY12/13:  6622/30411*/
/*CY12:  78/3579/16959*/
proc sql;
select count(*) as infractions, count(distinct doc_num) as offenders, count(distinct facname) as facility
from reneephi.Z_multiple_infractions_final;
run;









/*FINAL TABLE CREATION WITH JUST NEEDED RECORDS*/
/*kicking out: delayed incarcerates, small race categories, 0% or 100%+ time served (errant)*/
/*note:  life, lwop, and death offenders are in right now*/
/***do i really even need to omit pct served; keep as a validity check.  need to make sure had ample days to remove, and this is contingent on an accurate admit/rel date***/
/*CY12:  78/3,366/15,304 infractions*/
proc sql;
drop table reneephi.Z_miscon_finalb1;
create table reneephi.Z_miscon_finalb1 as (
select *
      ,(case  
	     when diff = 0 and diff2<>0 and priors = 'Y' then 'Y'
		 when diff = 0 and diff2=0  and priors = 'Y' then 'N'
		 else priors
		end) as priors_rc
from reneephi.z_days_to_miscon_final
where (pct_served >0 /*less than 0% served are bad admit/total term values*/
or pct_served <=1) /*less than 100% served-those over 100% are bad admit/total term values (e.g., 123933 is 2 when should be 25 years)*/
and race in ('W', 'B', 'I', 'H') /*kicking out Asian, Other, Pacific Islander b/c make up 25 offenders/111 misconducts*/
AND CONT_CALC <> 'DELINCAR' /*removing delayed incarcerations*/
and days_to_take = 'Y'
and cont_calc not in ('LIFE', 'LIFEWOP', 'DEATH') /*Can earn, but only applied in the event of a commutation - see below notes -maybe skewed application so omit*/
and total_term < 45 /*remove these because considered life sentence, too*/
)
;
run; 

/*elimination process to get data reduction numbers for methods section*/
proc sql;
select count(*) as infractions, count(distinct doc_num) as offenders
from reneephi.z_days_to_miscon_final
where (pct_served <=1
or pct_served >0)
and race in ('W', 'B', 'I', 'H') 
AND CONT_CALC <> 'DELINCAR'
and days_to_take = 'Y'
and (cont_calc in ('LIFE', 'LIFEWOP', 'DEATH') /*Can earn, but only applied in the event of a commutation - see below notes -maybe skewed application so omit*/
or total_term >= 45) /*remove these because considered life sentence, too*/
;
run; 





/*couting pop: CY12:  78/3,366/15,304 infractions*/ 
proc sql;
select count(*) as infractions, count(distinct doc_num) as offenders, count(distinct facname) as facility
from reneephi.Z_miscon_finalb1;
run;









/**********************************/
/****FINALL FULL SAMPLE*****
CY12/13:  6,226 and 27,439 infractions
CY12:  78/3,366/15,304 infractions*/
/**********************************/
DATA reneephi.Z_miscon_finalb1;
 set reneephi.Z_miscon_finalb1;

 /*MORE RECODES ON RQ.3 DV - ADJUST DAYS - FEMALES X ARE JUST BINARY SO CANNOT DO RQ.3*/
 /*note: cannot do B or X for females because they really just have binary*/
 /*so addressed through RQ.4*/
 IF miscon_class ='B' AND adjust_days_rc >=1  AND ADJUST_DAYS_RC <=30 THEN ADJUST_DAYS_B = 0;
 IF miscon_class ='B' AND adjust_days_rc >=31 AND ADJUST_DAYS_RC <=45 THEN ADJUST_DAYS_B = 1;
 IF miscon_class ='B' AND adjust_days_rc >=46 AND ADJUST_DAYS_RC <=60 THEN ADJUST_DAYS_B = 2;
 
 IF miscon_class ='A' AND adjust_days_rc >=1  AND ADJUST_DAYS_RC <=30  THEN ADJUST_DAYS_A = 0;
 IF miscon_class ='A' AND adjust_days_rc >=31 AND ADJUST_DAYS_RC <=60  THEN ADJUST_DAYS_A = 1;
 IF miscon_class ='A' AND adjust_days_rc >=61 AND ADJUST_DAYS_RC <=90  THEN ADJUST_DAYS_A = 2;
 IF miscon_class ='A' AND adjust_days_rc >=91 AND ADJUST_DAYS_RC <=180 THEN ADJUST_DAYS_A = 3;

 IF miscon_class ='X' AND adjust_days_rc >=1   AND ADJUST_DAYS_RC <=100 THEN ADJUST_DAYS_X = 0;
 IF miscon_class ='X' AND adjust_days_rc >=101 AND ADJUST_DAYS_RC <=200 THEN ADJUST_DAYS_X = 1;
 IF miscon_class ='X' AND adjust_days_rc >=201 AND ADJUST_DAYS_RC <=300 THEN ADJUST_DAYS_X = 2;
 IF miscon_class ='X' AND adjust_days_rc >=301 AND ADJUST_DAYS_RC <=365 THEN ADJUST_DAYS_X = 3;


  /*segregation*/
 IF SEX = 'M' AND miscon_class ='X' AND sancx1>=1 or sanc1x>=1 then mx_seg =1; else mx_seg= 0;

/*CATEGORICAL RECODES - WILL BE THE SAME ACROSS ALL MODELS - WILL DO CONTINOUS RECODES IN THE RQ SUBSAMPLES*/
 /*misconduct type violent nonviolent*/
 if miscon_type = 'Violent' then miscon_violent=1; else miscon_violent=0; 

 /*prior infracations Y/N bc so skewed and not sure how to handle zeroes*/
 if prior_infractions ='Y' then prior_miscons=1; else prior_miscons=0;
 if priors_rc = 'Y' then prior_viols =1; else prior_viols=0;

 /*prior incarcerations*/
 if prior_incs > 0 then prior_incs_rc =1; else prior_incs_rc = 0;

 /*sex*/
 if sex = 'M' then male =1; else male=0;

 /*race: centering done in each model*/
 if race = 'B' then black =1; else black =0;
 if race = 'H' then hispanic =1; else hispanic =0;
 if race = 'I' then nativeam =1; else nativeam =0;
 if race = 'W' then white =1; else white =0;

 /*education - nulls get set to no hsd*/
 if education in ('GED','High School Diploma','College not completed','Associates Degree','College Graduate','Under Graduate'
                 ,'Post Graduate, not completed','Vocational Tech') then hsd_least=1; else hsd_least=0;

 /*quadratic terms - see below in code*/

 /*violent crime*/
 if oms_violent_curr = 'Y' then violent=1; else violent=0;

  /*85% crime*/
 if eightyfivepercent= 'Y' then eighty5=1; else eighty5=0;

 /*mhl missing dummy code*/
 if mhl_cat =. then mhl_sysmiss=1; else mhl_sysmiss =0;

 /*private facility*/
 if factype =: 'Private' then private=1; else private=0;

 /*facility security*/
 if security = 'MAX' then maximum=1; else maximum=0;
 if security = 'MED' then medium=1; else medium=0;
 if security = 'MIN' or security = 'OUT' then minimum=1; else minimum=0;

 /*facility security*/
 if security_rc = 'MAX/MED' then maxmed=1; else maxmed=0;
 if security_rc = 'MIN' then minimum=1; else minimum=0;
 if security_rc = 'COMM' or security_rc = 'OUT' then community=1; else community=0;

 /*facility type (group n=3 EMP into GPS*/
 IF factype in ('Electronic Monitoring Program') then fac_type_rc = 'Global Positioning System'; else fac_type_rc=factype;

 /*days removed RQ.2*/
 if days_removed = 'Y' then days_removed_rc=1; else days_removed_rc=0;

 /*maxed out RQ.4*/
 if penalty_status = 'MaxedOutPenalty' then maxed_out=1; else maxed_out=0;

 /*total sanctions received*/
 tot_sanctions = SANCX1+SANCX2+SANCX3+SANCX4+SANCX5+SANCX6+SANCX7+SANC1X+SANC2X+SANC3X+SANC4X+SANC5X+SANC6X+SANC7X+SANCA1+SANCA2+SANCA3+SANCA4+SANCA5+SANCA6+SANCA7+SANCA8+SANCA9+SANC1A+SANC2A+SANC3A+SANC4A+SANC5A+SANC6A+SANC7A+SANC8A+SANC9A+SANCB1+SANCB2+SANCB3+SANCB4+SANCB5+SANCB6+SANCB7+SANCB8+SANCB9+SANC1B+SANC2B+SANC3B+SANC4B+SANC5B+SANC6B+SANC7B+SANC8B;

 /*recoding facname into a number*/
 if facname = 'ADAIR COUNTY JAIL'                              then fac_id = 1;  
 if facname = 'ALTUS CWC'                                      then fac_id = 2;  
 if facname = 'ARDMORE CWC'                                    then fac_id = 3;  
 if facname = 'AVALON HWH'                                     then fac_id = 4;  
 if facname = 'BEAVER CWC'                                     then fac_id = 5;  
 if facname = 'BRIDGEWAY HWH'                                  then fac_id = 6;  
 if facname = 'CARTER COUNTY CWC'                              then fac_id = 7;  
 if facname = 'CARVER HWH'                                     then fac_id = 8;  
 if facname = 'CATALYST-CAMEO HWH'                             then fac_id = 9;  
 if facname = 'CATALYST-ENID HWH FEMALES'                      then fac_id = 10; 
 if facname = 'CENTER POINT HWH'                               then fac_id = 11; 
 if facname = 'CENTER POINT HWH FEMALES'                       then fac_id = 12; 
 if facname = 'CENTER POINT OSAGE HWH'                         then fac_id = 13; 
 if facname = 'CENTRAL DISTRICT EMP'                           then fac_id = 14; 
 if facname = 'CENTRAL DISTRICT GPS'                           then fac_id = 15; 
 if facname = 'CHARLES E. BILL JOHNSON CORR. CENTER'           then fac_id = 16; 
 if facname = 'CHOCTAW COUNTY JAIL'                            then fac_id = 17; 
 if facname = 'CIMARRON CORRECTIONAL FACILITY'                 then fac_id = 18; 
 if facname = 'CLARA WATERS COMMUNITY CORR. CENTER'            then fac_id = 19; 
 if facname = 'COMANCHE COUNTY JAIL'                           then fac_id = 20; 
 if facname = 'COTTON COUNTY JAIL'                             then fac_id = 21; 
 if facname = 'CRAIG COUNTY JAIL'                              then fac_id = 22; 
 if facname = 'CREEK COUNTY JAIL'                              then fac_id = 23; 
 if facname = 'DAVIS CORRECTIONAL FACILITY-HOLDENVILLE'        then fac_id = 24; 
 if facname = 'DAVIS CWC'                                      then fac_id = 25; 
 if facname = 'DR. EDDIE WARRIOR CORRECTIONAL CENTER'          then fac_id = 26; 
 if facname = 'DRUG RECOVER, INC-IVAN HWH'                     then fac_id = 27; 
 if facname = 'ELK CITY CWC'                                   then fac_id = 28; 
 if facname = 'ENID CCC'                                       then fac_id = 29; 
 if facname = 'FREDERICK CWC'                                  then fac_id = 30; 
 if facname = 'GREAT PLAINS CORRECTIONAL FACILITY'             then fac_id = 31; 
 if facname = 'HILLSIDE CCC'                                   then fac_id = 32; 
 if facname = 'HOBART CWC'                                     then fac_id = 33; 
 if facname = 'HOLLIS CWC'                                     then fac_id = 34; 
 if facname = 'HOWARD MCLEOD CORRECTIONAL CENTER'              then fac_id = 35; 
 if facname = 'IDABEL CWC'                                     then fac_id = 36; 
 if facname = 'JACKIE BRANNON CORRECTIONAL CENTER'             then fac_id = 37; 
 if facname = 'JAMES CRABTREE CORRECTIONAL CENTER'             then fac_id = 38; 
 if facname = 'JEFFERSON COUNTY JAIL'                          then fac_id = 39; 
 if facname = 'JESS DUNN CORRECTIONAL CENTER'                  then fac_id = 40; 
 if facname = 'JIM E HAMILTON CORRECTIONAL CENTER'             then fac_id = 41; 
 if facname = 'JOHN LILLEY CORRECTIONAL CENTER'                then fac_id = 42; 
 if facname = 'JOSEPH HARP CORRECTIONAL CENTER'                then fac_id = 43; 
 if facname = 'KATE BARNARD CCC'                               then fac_id = 44; 
 if facname = 'LAWTON CCC'                                     then fac_id = 45; 
 if facname = 'LAWTON CORRECTIONAL FACILITY'                   then fac_id = 46; 
 if facname = 'LEFLORE COUNTY JAIL'                            then fac_id = 47; 
 if facname = 'LEX ASSESSMENT & RECEPTION CENTER'              then fac_id = 48; 
 if facname = 'LEXINGTON CORRECTIONAL CENTER'                  then fac_id = 49; 
 if facname = 'MABEL BASSETT ASSESSMENT & RECEPTION CEN'       then fac_id = 50; 
 if facname = 'MABEL BASSETT CORRECTIONAL CENTER'              then fac_id = 51; 
 if facname = 'MACK ALFORD CORRECTIONAL CENTER'                then fac_id = 52; 
 if facname = 'MADILL CWC'                                     then fac_id = 53; 
 if facname = 'MAJOR COUNTY JAIL'                              then fac_id = 54; 
 if facname = 'MANGUM CWC'                                     then fac_id = 55; 
 if facname = 'MARSHALL COUNTY JAIL'                           then fac_id = 56; 
 if facname = 'MUSKOGEE CCC'                                   then fac_id = 57; 
 if facname = 'NORTHEAST DISTRICT GPS'                         then fac_id = 58; 
 if facname = 'NORTHEAST OKLAHOMA CORR. CENTER'                then fac_id = 59; 
 if facname = 'NORTHWEST DISTRICT EMP'                         then fac_id = 60; 
 if facname = 'NORTHWEST DISTRICT GPS'                         then fac_id = 61; 
 if facname = 'NOWATA COUNTY JAIL'                             then fac_id = 62; 
 if facname = 'OKLAHOMA CITY CCC'                              then fac_id = 63; 
 if facname = 'OKLAHOMA COUNTY JAIL'                           then fac_id = 64; 
 if facname = 'OKLAHOMA HWH'                                   then fac_id = 65; 
 if facname = 'OKLAHOMA STATE PENITENTIARY'                    then fac_id = 66; 
 if facname = 'OKLAHOMA STATE REFORMATORY'                     then fac_id = 67; 
 if facname = 'OKMULGEE COUNTY JAIL'                           then fac_id = 68; 
 if facname = 'OTTAWA COUNTY JAIL'                             then fac_id = 69; 
 if facname = 'PUSHMATAHA COUNTY JAIL'                         then fac_id = 70; 
 if facname = 'R.B. DICK CONNER CORRECTIONAL CENTER'           then fac_id = 71; 
 if facname = 'RIVERSIDE HWH'                                  then fac_id = 72; 
 if facname = 'ROGER MILLS COUNTY JAIL'                        then fac_id = 73; 
 if facname = 'SAYRE CWC'                                      then fac_id = 74; 
 if facname = 'SEQUOYAH COUNTY JAIL'                           then fac_id = 75; 
 if facname = 'SOUTHEAST DISTRICT GPS'                         then fac_id = 76; 
 if facname = 'SOUTHWEST DISTRICT GPS'                         then fac_id = 77; 
 if facname = 'TILLMAN COUNTY JAIL'                            then fac_id = 78; 
 if facname = 'TULSA COUNTY GPS'                               then fac_id = 79; 
 if facname = 'TURLEY HWH'                                     then fac_id = 80; 
 if facname = 'UNION CITY CCC'                                 then fac_id = 81; 
 if facname = 'WALTERS CWC'                                    then fac_id = 82; 
 if facname = 'WAURIKA CWC'                                    then fac_id = 83; 
 if facname = 'WILLIAM S. KEY CORRECTIONAL CENTER'             then fac_id = 84; 

 /*recoding into a character*/
 fac_id_var = left(put(fac_id,6.));

;
run;



/*****REMOVING DOWN TO ONE RECORD MULTIPLE INFRACTIONS ON SAME DAY*****/
/*CHECK FULL POPULATION FOR DATA REDUCTION:  SEEING IF I AM DOING IT RIGHT*/
proc sql;
drop table r_test;
create table r_test as (
select doc_num, fac_id, cont_calc, days_to_take, days_removed, sufficient_days, offence_date, miscon_class, adjust_days_rc
      ,miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,days_removed_rc, maxed_out, adjust_days_b, adjust_days_a, adjust_days_x, prison_admit_date, prison_exit_date, sex, race 
from reneephi.Z_miscon_finalb1
) order by DOC_NUM, offence_date;
run;


/*STEP 1: ALL SINGLE INFRACTIONS FOR EACH DAY*/
proc sql;
drop table reneephi.z_single_events;
create table reneephi.z_single_events as
(select doc_num, fac_id, cont_calc, days_to_take, days_removed, sufficient_days, offence_date, miscon_class, adjust_days_rc
       ,miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
       ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
       ,private, maxmed, minimum, community 
       ,days_removed_rc, maxed_out, adjust_days_b, adjust_days_a, adjust_days_x, prison_admit_date, prison_exit_date, sex, race  
from reneephi.Z_miscon_finalb1
where multiple_miscon = 0
) order by doc_num, offence_date;
run; 


/*STEP 2: ALL MULITLPLE INFRACTIONS FOR EACH DAY*/
/*keeping just the worst infraction if multiple were given on the same day*/
/*worst = highest level (B,A,X) and then days removed (. through 365)*/
proc sql;
drop table reneephi.z_multiple_events;
create table reneephi.z_multiple_events as (
select distinct doc_num, fac_id, offence_date, level, adjust_days_rc, tot_sanctions, miscon_Violent
from reneephi.Z_miscon_finalb1
where multiple_miscon = 1
group by doc_num, offence_date
having level = max(level)
and adjust_days_rc =  max(adjust_days_rc)
and miscon_violent = max(miscon_Violent)
/*and tot_sanctions = max(tot_sanctions) :  giving me problems when this and adjust_days_rc both in*/
)
;
run;

/*STEP 3: LINK WORST MULTIPLE INFRACTION TO ITS ORIGINAL FIELDS*/
proc sql;
drop table reneephi.z_multiples_link;
create table reneephi.z_multiples_link as (
select distinct m.doc_num, e.fac_id, e.cont_calc, e.days_to_take, e.days_removed, e.sufficient_days, e.offence_date
               ,(case 
                  when m.level= 1 then 'B'
                  when m.level= 2 then 'A'
                  when m.level= 3 then 'X'
                 end) as miscon
               ,m.adjust_days_rc
               ,e.miscon_violent, e.prior_viols, e.days, e.multiple_miscon, e.pct_served_upto_miscon, e.tot_sanctions
               ,e.sex, e.male, e.race, e.black, e.hispanic, e.nativeam, e.white, e.hsd_least, e.age_at_miscon, e.prior_incs_rc, e.total_term, e.violent, e.eighty5, e.lsi_score, e.mhl_sysmiss, e.mhl_cat, e.exit_mhl
               ,e.private, e.maxmed, e.minimum, e.community
               ,e.days_removed_rc ,e.maxed_out, adjust_days_b, adjust_days_a, adjust_days_x, prison_admit_date, prison_exit_date, sex, race  
from reneephi.z_multiple_events m
right join reneephi.Z_miscon_finalb1 e
on m.doc_num = e.doc_num
where m.offence_date = e.offence_date
and m.level = e.level
and m.tot_sanctions = e.tot_sanctions
and m.miscon_violent = e.miscon_violent
and m.adjust_days_rc = e.adjust_days_rc
) order by doc_num, offence_date
;
run;


/*STEP 3: UNION SINGLE AND MAX MULTIPLE EVENTS INTO ONE TABLE*/
proc sql;
drop table reneephi.z_final;
create table reneephi.z_final as (
select * from reneephi.z_single_events
union all
select * from reneephi.z_multiples_link) ORDER BY DOC_NUM, offence_Date;
run;

/*TESTING RESULTS*/
/*proc sql;
drop table TEST;
create table TEST as (
SELECT *
FROM reneephi.z_final
WHERE DOC_NUM = 496627)
ORDER BY DOC_NUM, OFFENCE_DATE;
RUN;*/

PROC SORT DATA=reneephi.z_final;
	BY doc_num fac_id;
RUN;

data reneephi.z_final;
set reneephi.z_final;
by doc_num fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*couting pop: CY12:  77/3,362/13,979 infractions*/ 
proc sql;
select exit_mhl, count(*) as infractions, count(distinct doc_num) as offenders, count(distinct FAC_ID) as facility
from reneephi.z_final
group by exit_mhl;
run;









/*priors-should be ready to delete, but keep in case find error. --still need to correct those that have >2 on first shot
proc sql;
create table r_test as
(select doc_num, row_id, prison_admit_date, offence_date, days_between_miscon, days_to_miscon, prior_infracs, 
  (case
    when days_to_miscon=0 and row_id-1=1 then 'N'
	when row_id=1 then 'N'
	else 'Y'
   end) as priors, multiple_miscon
from miscon_finalb1
where doc_num = '223800');
run;*/

/*TEST STUFF*/
/*proc sql;
create table work.r_temp as (
select doc_num, row_id, offence_date, days_to_miscon, priors_rc, multiple_miscon
/*,days_between_miscon, priors, diff, diff2, date
from reneephi.Z_miscon_finalb1 b
where doc_num = 586250);
run;*/
/*test cases: where doc_num in ('494585','486878')*/

/*proc sql;
create table work.temp as (
select distinct doc_num, count(*)
from reneephi.Z_miscon_finalb1 b
group by doc_num
);
run;*/

/*proc sql;
create table work.temp as (
select distinct doc_num, count(*)
from reneephi.Z_miscon_finalb1 b
group by doc_num
);
run;*/











/**********************************/
/**********************************/
/*******RESEARCH QUESTION #1*******/
/*Diff # infractions received, 
  by race, gender, race*gender - 
  across infraction class*/
/**********************************/
/**********************************/

/***--------------***/
/***--ANOVA DATA--***/
/***--------------***/

/*PART 1:  HERE I AM ROLLING UP 
           THE NUMBER OF INFRACTIONS 
           BY MISCONDUCT CLASS (B, A, X)
           INTO A RATIO BY OFFENDER*/
         /*THIS IS OFFENDER-LEVEL (LEVEL 2) INFORMATION*/
proc sql;
drop table reneephi.Z_RQ1;
create table reneephi.Z_RQ1 as (
select distinct doc_num
      ,sex
	  ,race
	  ,SEX||RACE AS SEXRACE
      ,miscon_class
      ,(count(*)/((prison_exit_date - prison_admit_date)/365.25)) AS ratio
from reneephi.z_final
/*where doc_num NOT IN (591356,634401,547584,579988,623241,639035,618351,657079,600702,664473,600702,678871  
                     ,456725,633191,613655,654889,634923,623883,680921,676565,615763,256213)*/
group by doc_num
        ,sex
	    ,race
		,SEX||RACE
        ,miscon_class
)
;
run;

/*dropped cases that were identified as outliers using the Outlier Labeling Rule*/
proc sql;
drop table reneephi.Z_RQ1_race;
create table reneephi.Z_RQ1_race as (
select doc_num
      ,sex
	  ,race
	  ,SEX||RACE AS SEXRACE
      ,miscon_class
      ,ratio
from reneephi.Z_RQ1
where (miscon_class = 'B' 
       and ((race = 'B' and ratio <1.76)
         or (race = 'H' and ratio <1.86)
	     or (race = 'I' and ratio <2.08)
	     or (race = 'W' and ratio <2.00)))
or    (miscon_class = 'A' 
       and ((race = 'B' and ratio <3.71)
         or (race = 'H' and ratio <3.64)
	     or (race = 'I' and ratio <3.87)
	     or (race = 'W' and ratio <3.67)))
or    (miscon_class = 'X' 
       and ((race = 'B' and ratio <1.62)
         or (race = 'H' and ratio <2.24)
	     or (race = 'I' and ratio <2.13)
	     or (race = 'W' and ratio <1.77)))
)
;
run;

where (miscon_class = 'B' 
       and ((race = 'B' and ratio <1.45)
         or (race = 'H' and ratio <1.53)
	     or (race = 'I' and ratio <1.71)
	     or (race = 'W' and ratio <1.65)))
or    (miscon_class = 'A' 
       and ((race = 'B' and ratio <3.04)
         or (race = 'H' and ratio <2.99)
	     or (race = 'I' and ratio <3.20)
	     or (race = 'W' and ratio <3.04)))
or    (miscon_class = 'X' 
       and ((race = 'B' and ratio <1.35)
         or (race = 'H' and ratio <1.85)
	     or (race = 'I' and ratio <1.76)
	     or (race = 'W' and ratio <1.46)))



/*--sample size BY INFRACTION CLASS*/
/*inmates can stretch across b, a, x, so Ns are larger than expected*/
proc sql;
select miscon_class, count(*) as infractions, count(distinct doc_num) as offenders
from reneephi.Z_RQ1
group by miscon_class;
run;


/*BOX PLOT OF DATA*/
PROC SORT
	DATA=reneephi.Z_RQ1_race
	OUT=reneephi.Z_RQ1_race
	;
	BY miscon_class race;
RUN;
proc boxplot data=reneephi.Z_RQ1_race;
WHERE MISCON_CLASS = 'B';
BY miscon_class RACE;
plot ratio*race;
run;



/*PART 2:  HAVE TO SORT DATA BY THE 'BY' VARIABLE - HERE IT IS MISCONDUCT CLASS*/
PROC SORT
	DATA=reneephi.Z_RQ1
	OUT=reneephi.Z_RQ1
	;
	BY miscon_class;
RUN;


/*PART 4:  T-TEST FOR GENDER*/
PROC ttest DATA=reneephi.Z_RQ1;
BY miscon_class;
  CLASS SEX;
  var ratio;
RUN; 
QUIT;


proc univariate data=reneephi.Z_RQ1_race robustscale plot ;
WHERE MISCON_CLASS = 'X';
BY RACE;
var ratio;
run; 

/*PART 5:  ANOVA FOR RACE*/
PROC SORT
	DATA=reneephi.Z_RQ1_race
	OUT=reneephi.Z_RQ1_race
	;
	BY miscon_class RACE;
RUN;
PROC glm DATA=reneephi.Z_RQ1_race;
BY miscon_class;
  CLASS RACE;
  MODEL ratio=RACE;
  LSMEANS RACE / ADJUST=TUKEY alpha=0.05;  
RUN; 
QUIT;




proc means data=reneephi.Z_RQ1_race n mean std min max;
BY miscon_class RACE;
WHERE MISCON_CLASS = 'B';
VAR ratio;
run;



/*PART 6:  T-TEST FOR RACE*GENDER FOR BLACKS*/
PROC ttest DATA=reneephi.Z_RQ1;
WHERE RACE = 'B';
BY miscon_class;
  CLASS SEXRACE;
  VAR RATIO;
RUN; 
QUIT;

/*PART 7:  T-TEST FOR RACE*GENDER FOR WHITES*/
PROC ttest DATA=reneephi.Z_RQ1;
WHERE RACE = 'W';
BY miscon_class;
  CLASS SEXRACE;
  VAR RATIO;
RUN; 
QUIT;

/*PART 8:  T-TEST FOR RACE*GENDER FOR NATIVE AMERICANS*/
PROC ttest DATA=reneephi.Z_RQ1;
WHERE RACE = 'I';
BY miscon_class;
  CLASS SEXRACE;
  VAR RATIO;
RUN; 
QUIT;

/*PART 9:  T-TEST FOR RACE*GENDER FOR HISPANICS*/
PROC ttest DATA=reneephi.Z_RQ1;
WHERE RACE = 'H';
BY miscon_class;
  CLASS SEXRACE;
  VAR RATIO;
RUN; 
QUIT;









/**********************************/
/**********************************/
/*******RESEARCH QUESTION #2*******/
/*Diff # sanctioned to credit loss, 
  by race, gender, race*gender - 
  across infraction class*/
/**********************************/
/**********************************/


proc sql;
drop table reneephi.Z_RQ2;
create table reneephi.Z_RQ2 as (
select *
from reneephi.z_final
)
;
run;


/*OVERALL DESCRIPTIVE VIEW OF WHO SANCTIONED TO LOSE EARNED CREDITS*/
proc sql;
select count(*) as infractions, count(distinct doc_num) as offenders, count(distinct fac_id) as facility
from reneephi.Z_RQ2;
run;

proc sql;
select male, days_removed_rc, count(distinct doc_num) as offenders
from reneephi.Z_RQ2
group by male, days_removed_rc;
run;

proc sql;
select race, days_removed_rc, count(distinct doc_num) as offenders
from reneephi.Z_RQ2
group by race, days_removed_rc;
run;


/*stratified sampling???*/
/*proc surveyselect data=Z_RQ2
   method=srs n=(500,500) out=SampleSRS;
   strata by male;
run;*/


/*RUN ALL THESE BECAUSE MODEL SUBSETS: since private/public prison is not stat. sig., can omit variable and run as non-gender specific model!*/
proc sql;
drop table reneephi.Z_RQ2_B;
create table reneephi.Z_RQ2_B as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,days_removed_rc
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
      ,log(pct_served_upto_miscon) as pct_served_log
	  ,(days/30.42) as mths_to_miscon
	  ,'B' as dataset
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ2
where MISCON_CLASS = 'B'
)
;
run;

proc sql;
drop table reneephi.Z_RQ2_A;
create table reneephi.Z_RQ2_A as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,days_removed_rc
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
      ,log(pct_served_upto_miscon) as pct_served_log
	  ,(days/30.42) as mths_to_miscon
	  ,'A' as dataset
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ2
where MISCON_CLASS = 'A'
)
;
run;

proc sql;
drop table reneephi.Z_RQ2_X;
create table reneephi.Z_RQ2_X as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, RACE, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,days_removed_rc
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
      ,log(pct_served_upto_miscon) as pct_served_log
	  ,(days/30.42) as mths_to_miscon
	  ,'X' as dataset
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ2
where MISCON_CLASS = 'X'
)
;
run;

/*--sample sizes for all subsets:  B, A, X*/
proc sql;
select 'B' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ2_B
UNION ALL
select 'A' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ2_A
UNION ALL
select 'X' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ2_X
run;


/*AGGREGATE TO COMPARE DIFFERENCES ACROSS INFRACTION CLASSES*/
proc sql;
drop table reneephi.r_RQ2_aggregate;
create table reneephi.r_RQ2_aggregate as (
select *
from reneephi.Z_RQ2_B
UNION ALL
select *
from reneephi.Z_RQ2_A
UNION ALL
select *
from reneephi.Z_RQ2_X
);
run;

/*miscon_violent, prior_viols, mths_to_miscon, multiple_miscon, tot_sanctions 
male, black, hispanic, nativeam, white, age_at_miscon, hsd_least, lsi_score, prior_incs_rc, total_term, violent, eighty5, pct_served_upto_miscon
maxmed, minimum, community*/

/*ANOVA FOR CONTINUOUS*/
PROC SORT
	DATA=reneephi.Z_RQ2_X
	OUT=reneephi.Z_RQ2_X
	;
	BY MALE;
RUN;

PROC ttest DATA=reneephi.Z_RQ2_X;
  CLASS MALE;
  VAR RATIO;
RUN; 
QUIT;

PROC glm DATA=reneephi.Z_RQ2_X;
  CLASS MALE;
  MODEL days_removed_rc=MALE;
  LSMEANS MALE / ADJUST=TUKEY alpha=0.05;  
RUN; 
QUIT;









/*RQ.2: CLASS Bs*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq2_b n mean std min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white  age_at_miscon hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ days_removed_rc;
run;

/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq2_b;
 model days_removed_rc = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon hsd_least  lsi_score  exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;


/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_RQ2_b;
	BY fac_id;
RUN;

data reneephi.Z_RQ2_b;
set reneephi.Z_RQ2_b;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_RQ2_b;
	BY fac doc_num;
RUN;

data reneephi.Z_RQ2_b;
set reneephi.Z_RQ2_b;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_RQ2_b;
	BY fac person;
RUN;

data reneephi.Z_RQ2_b;
set reneephi.Z_RQ2_b;
record=_n_;
run;



proc sql;
drop table reneephi.z_RQ2b_f;
create table reneephi.z_RQ2b_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_RQ2_B m);
run;

/*don't need to recreate: just check to see it's still okay with each open*/
proc sql;
select *
from reneephi.z_RQ2b_f;
run;



/*PROC SORT DATA=reneephi.z_RQ2b_f;
	BY person;
RUN;*/

/*PREDICTIVE*/
/*MLM: unconditional model*/
PROC GLIMMIX DATA=reneephi.z_RQ2b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) =  / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2b_f METHOD=rmpl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) =  /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                                     / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=200 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept male  black  hispanic  nativeam age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM: level 1+2+3 fixed/random efffects*/
PROC GLIMMIX DATA=reneephi.z_RQ2b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
								    /*level 3*/ maxmed  minimum
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;  /*male black hispanic:  this run taking them out to get L1 and L2 fixed only*/
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;











/*RQ.2: CLASS As*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq2_a n mean std min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white age_at_miscon hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ days_removed_rc;
run;

/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq2_a;
 model days_removed_rc = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;


/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_RQ2_a;
	BY fac_id;
RUN;

data reneephi.Z_RQ2_a;
set reneephi.Z_RQ2_a;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_RQ2_a;
	BY fac doc_num;
RUN;

data reneephi.Z_RQ2_a;
set reneephi.Z_RQ2_a;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_RQ2_a;
	BY fac person;
RUN;

data reneephi.Z_RQ2_a;
set reneephi.Z_RQ2_a;
record=_n_;
run;



proc sql;
drop table reneephi.z_RQ2a_f;
create table reneephi.z_RQ2a_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_RQ2_a m);
run;





PROC SORT DATA=reneephi.z_RQ2a_f;
	BY person_var;
RUN;

/*PREDICTIVE*/
/*MLM 1: unconditional model*/
PROC GLIMMIX DATA=reneephi.z_RQ2a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) =  / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 2: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) =  /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                                     / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 3: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 4: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept male  black  hispanic  nativeam age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 5: level 1+2+3 fixed/random efffects*/ 
PROC GLIMMIX DATA=reneephi.z_RQ2a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ miscon_violent prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
								    /*level 3*/ maxmed  minimum
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;  /*male black hispanic:  this run taking them out to get L1 and L2 fixed only*/
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;







/*RQ.2: CLASS Xs*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq2_x n mean stderr min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white  age_at_miscon  hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ days_removed_rc;
run;


/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq2_x;
 model days_removed_rc = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon  hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;


/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_RQ2_x;
	BY fac_id;
RUN;

data reneephi.Z_RQ2_x;
set reneephi.Z_RQ2_x;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_RQ2_x;
	BY fac doc_num;
RUN;

data reneephi.Z_RQ2_x;
set reneephi.Z_RQ2_x;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_RQ2_x;
	BY fac person;
RUN;

data reneephi.Z_RQ2_x;
set reneephi.Z_RQ2_x;
record=_n_;
run;

proc sql;
drop table reneephi.Z_RQ2x_f;
create table reneephi.z_RQ2x_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_RQ2_x m);
run;


proc sql;
select *
from reneephi.z_RQ2x_f;
run;


PROC SORT DATA=reneephi.z_RQ2x_f;
	BY person;
RUN;

/*PREDICTIVE*/
/*MLM 1: unconditional model*/
PROC GLIMMIX DATA=reneephi.z_RQ2x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) =  / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 2: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) =  /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                                     / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 3: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 4: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ2x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept male  black  hispanic  nativeam age_at_miscon /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 5: level 1+2+3 fixed/random efffects*/ 
PROC GLIMMIX DATA=reneephi.z_RQ2x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL days_removed_rc(event=last) = /*level 1*/ miscon_violent prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                                    /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                                    /*level 2 interacts*/ male*black  
                                                          male*hispanic  
                                                          male*nativeam  
                                                          male*age_at_miscon 
                                                          black*age_at_miscon 
                                                          hispanic*age_at_miscon 
                                                          nativeam*age_at_miscon 
                                                          male*black*age_at_miscon  
                                                          male*hispanic*age_at_miscon  
                                                          male*nativeam*age_at_miscon
								    /*level 3*/ maxmed  minimum
                                    / CL DIST=binary LINK=logit SOLUTION ddfm=residual;
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;  
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;


















/**********************************/
/**********************************/
/*******RESEARCH QUESTION #3*******/
/*race, gender predict time lost by
  infraction class*/
/**********************************/
/**********************************/


/*PART 1:  HERE I CREATE MY DATASETS WHERE I ONLY KEEP THOSE WHO HAD DAYS REMOVED AND HAD SUFFICIENT DAYS AVAILABLE*/
proc sql;
drop table reneephi.z_rq3;
create table reneephi.z_RQ3 as (
select *
from reneephi.z_final
where days_removed ='Y' /*sanctioned to lose days*/
and sufficient_days = 'Y' /*only those who could lose the full range possible*/
)
;
run;


/*--sample sizes for all subsets:  B, A, X*/
proc sql;
select count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.z_rq3;
run;


/*OVERALL DESCRIPTIVE VIEW OF DAYS REMOVED*/
proc sql;
select MISCON_CLASS, avg(adjust_days_rc), count(distinct doc_num) as offenders
from reneephi.z_RQ3
group by MISCON_CLASS;
run;

proc sql;
select MISCON_CLASS, male, avg(adjust_days_rc), count(distinct doc_num) as offenders
from reneephi.z_RQ3
group by MISCON_CLASS, male;
run;

proc sql;
select MISCON_CLASS, race, avg(adjust_days_rc), count(distinct doc_num) as offenders
from reneephi.z_RQ3
group by MISCON_CLASS, race;
run;



/*RUN ALL THESE BECAUSE MODEL SUBSETS*/
proc sql;
drop table reneephi.Z_RQ3_B;
create table reneephi.Z_RQ3_B as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,ADJUST_DAYS_B
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
      ,log(pct_served_upto_miscon) as pct_served_log
	  ,(days/30.42) as mths_to_miscon
	  ,(case when sufficient_days = 'Y' then 1 else 0 end) as suff_day
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ3
where MISCON_CLASS = 'B'
and male = 1 /*only binary outcome, so females excluded*/
)
;
run;

proc sql;
drop table reneephi.Z_RQ3_A;
create table reneephi.Z_RQ3_A as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,ADJUST_DAYS_A
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
      ,log(pct_served_upto_miscon) as pct_served_log
	  ,(days/30.42) as mths_to_miscon
	  ,(case when sufficient_days = 'Y' then 1 else 0 end) as suff_day
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ3
where MISCON_CLASS = 'A'
)
;
run;

proc sql;
drop table reneephi.Z_RQ3_X;
create table reneephi.Z_RQ3_X as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,ADJUST_DAYS_X
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
      ,log(pct_served_upto_miscon) as pct_served_log
	  ,(days/30.42) as mths_to_miscon
	  ,(case when sufficient_days = 'Y' then 1 else 0 end) as suff_day
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ3
where MISCON_CLASS = 'X'
and male = 1 /*only binary outcome, so females excluded*/
)
;
run;




/*--sample sizes for all subsets:  B, A, X*/
proc sql;
select 'B' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ3_B
UNION ALL
select 'A' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ3_A
UNION ALL
select 'X' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ3_X
run;






/*RQ.3: CLASS Bs*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq3_b n mean std min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white age_at_miscon  hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ ADJUST_DAYS_B;
run;

/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq3_b;
 model ADJUST_DAYS_B = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;




/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_rq3_b;
	BY fac_id;
RUN;

data reneephi.Z_rq3_b;
set reneephi.Z_rq3_b;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_rq3_b;
	BY fac doc_num;
RUN;

data reneephi.Z_rq3_b;
set reneephi.Z_rq3_b;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_rq3_b;
	BY fac person;
RUN;

data reneephi.Z_rq3_b;
set reneephi.Z_rq3_b;
record=_n_;
run;

proc sql;
drop table reneephi.Z_RQ3B_f;
create table reneephi.z_RQ3B_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq3_b m);
run;





/*PREDICTIVE*/
/*MLM: unconditional model*/
PROC GLIMMIX DATA=reneephi.z_RQ3b_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_B = / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=120 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3b_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_B = /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=120 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3b_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_B = /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                      /*level 2*/ black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/black*age_at_miscon  hispanic*age_at_miscon  nativeam*age_at_miscon /*because a male-only analysis*/
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=120 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3b_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_B = /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                      /*level 2*/ black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/black*age_at_miscon  hispanic*age_at_miscon  nativeam*age_at_miscon /*because a male-only analysis*/
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept  black  hispanic  nativeam age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=1000 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 5: level 1+2+3 fixed/random efffects*/ 
PROC GLIMMIX DATA=reneephi.z_RQ3b_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_B (ref=last) = /*level 1*/ prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                      /*level 2*/ black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/ black*age_at_miscon  hispanic*age_at_miscon  nativeam*age_at_miscon /*because a male-only analysis*/
					  /*level 3*/ maxmed  minimum
                      / CL DIST=MULTI LINK=gLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var group=adjust_days_b TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) group=adjust_days_b TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;









/*RQ.3: CLASS As*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq3_a n mean std min max;
var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white  age_at_miscon hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ ADJUST_DAYS_a;
run;

/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq3_a;
 model ADJUST_DAYS_a = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam age_at_miscon hsd_least  lsi_score prior_incs_rc exit_mhl  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;


/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_rq3_a;
	BY fac_id;
RUN;

data reneephi.Z_rq3_a;
set reneephi.Z_rq3_a;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_rq3_a;
	BY fac doc_num;
RUN;

data reneephi.Z_rq3_a;
set reneephi.Z_rq3_a;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_rq3_a;
	BY fac person;
RUN;

data reneephi.Z_rq3_a;
set reneephi.Z_rq3_a;
record=_n_;
run;

proc sql;
drop table reneephi.z_RQ3a_f;
create table reneephi.z_RQ3a_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq3_a m);
run;





PROC SORT DATA=reneephi.z_RQ3a_f;
	BY person;
RUN;


/*PREDICTIVE*/
/*MLM 1: unconditional model*/
PROC GLIMMIX DATA=reneephi.z_RQ3a_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_a = / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 2: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3a_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_a = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 3: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3a_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_a = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                      /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/ male*black  
                                            male*hispanic  
                                            male*nativeam  
                                            male*age_at_miscon 
                                            black*age_at_miscon 
                                            hispanic*age_at_miscon 
                                            nativeam*age_at_miscon 
                                            male*black*age_at_miscon  
                                            male*hispanic*age_at_miscon  
                                            male*nativeam*age_at_miscon
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 4: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3a_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_a = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                      /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/ male*black  
                                            male*hispanic  
                                            male*nativeam  
                                            male*age_at_miscon 
                                            black*age_at_miscon 
                                            hispanic*age_at_miscon 
                                            nativeam*age_at_miscon 
                                            male*black*age_at_miscon  
                                            male*hispanic*age_at_miscon  
                                            male*nativeam*age_at_miscon
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept male  black  hispanic  nativeam age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 5: level 1+2+3 fixed/random efffects*/ 
PROC GLIMMIX DATA=reneephi.z_RQ3a_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_a = /*level 1*/ miscon_violent prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                      /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/ male*black  
                                            male*hispanic  
                                            male*nativeam  
                                            male*age_at_miscon 
                                            black*age_at_miscon 
                                            hispanic*age_at_miscon 
                                            nativeam*age_at_miscon 
                                            male*black*age_at_miscon  
                                            male*hispanic*age_at_miscon  
                                            male*nativeam*age_at_miscon
					  /*level 3*/ maxmed  minimum
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;








/*RQ.3: CLASS Xs*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq3_x n mean std min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white  age_at_miscon hsd_least lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5 pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ ADJUST_DAYS_x;
run;


/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq3_x;
 model ADJUST_DAYS_x = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;

/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_rq3_x;
	BY fac_id;
RUN;

data reneephi.Z_rq3_x;
set reneephi.Z_rq3_x;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_rq3_x;
	BY fac doc_num;
RUN;

data reneephi.Z_rq3_x;
set reneephi.Z_rq3_x;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_rq3_x;
	BY fac person;
RUN;

data reneephi.Z_rq3_x;
set reneephi.Z_rq3_x;
record=_n_;
run;

proc sql;
drop table reneephi.z_RQ3x_f;
create table reneephi.z_RQ3x_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq3_x m);
run;

PROC SORT DATA=reneephi.z_RQ3x_f;
	BY person;
RUN;





/*PREDICTIVE*/
/*MLM 1: unconditional model*/
PROC GLIMMIX DATA=reneephi.z_RQ3x_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_x = / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 2: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3x_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_x = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 3: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3x_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_x = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                      /*level 2*/  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/ black*age_at_miscon  hispanic*age_at_miscon  nativeam*age_at_miscon /*male analysis only*/
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ3x_f METHOD=quad(fastquad qpoints=3) NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_x = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                      /*level 2*/  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/ black*age_at_miscon  hispanic*age_at_miscon  nativeam*age_at_miscon /*male analysis only*/
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept  black  hispanic  nativeam age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=300 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 5: level 1+2+3 fixed/random efffects*/ /*add in: age2, days_log, total_term_log,  pct_served_log*/
PROC GLIMMIX DATA=reneephi.z_RQ3x_f METHOD=rspl NOCLPRINT;
CLASS fac_var person_var;
MODEL ADJUST_DAYS_x = /*level 1*/ miscon_violent prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                      /*level 2*/  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score exit_mhl  prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                      /*level 2 interacts*/ black*age_at_miscon  hispanic*age_at_miscon  nativeam*age_at_miscon  /*male analysis only*/
					  /*level 3*/ maxmed  minimum
                      / CL DIST=MULTI LINK=CLOGIT SOLUTION ddfm=residual; 
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=200 gconv=1e-4;
COVTEST/WALD;
run;











/*PART 2B:  descriptive spaghetti PLOTTED between group differences*/

/*SEX AND DAYS*/
proc sgpanel data=work.RQ3 noautolegend;
panelby miscon_class;
reg x=adjust_days_rc y=sex; /*for race just replace sex*/


/*PART 2C:  descriptive BOX PLOT between group differences*/
/*SEX AND DAYS*/
title 'Adjust Days by Sex';
  proc sgplot data=work.RQ3;
  vbox adjust_days_rc / category=sex group=miscon_class connect=mean;  /*for race just replace sex*/
  xaxis display=(nolabel);
run;


/*PART 2D:  descriptive histogram and distributions of days adjusted*/
/*SEX AND DAYS*/
proc sort data=work.rq3;
by sex;
run;

ods graphics on;
proc surveymeans data = work.RQ3 plots = all;
where miscon_class = 'X';
by sex;
var adjust_days_rc;
run;
ods graphics off;

/*RACE AND DAYS*/
proc sort data=work.rq3;
by race;
run;

ods graphics on;
proc surveymeans data = work.RQ3 plots = all;
where miscon_class = 'A';
by race;
var adjust_days_rc;
run;
ods graphics off;


/*NOTE:
proc glimmix;
      class preference;
      model preference(order=freq ref=first) = feature price /
                      dist=multinomial 
                      link=glogit;
      random intercept / subject=store group=preference;
   run;
The ORDER=FREQ option arranges  categories by desc freq. The REF=FIRST option then selects the response category 
with lowest Ordered Value—the most frequent category—as the reference.*/

/************************************************/
/*how to handle OUT OF MEMORY: http://support.sas.com/kb/37/047.html*/
/*SAS commands for PROC GLIMMIX: https://support.sas.com/documentation/cdl/en/statug/63033/HTML/default/viewer.htm#statug_glimmix_a0000001405.htm#statug.glimmix.gmxoptplots*/
/*ESTIMATION TYPES: https://support.sas.com/documentation/cdl/en/statug/63033/HTML/default/viewer.htm#statug_glimmix_a0000001405.htm#statug.glimmix.gmxoptmethod*/
/************************************************/

















/**********************************/
/**********************************/
/*******RESEARCH QUESTION #4*******/
/*race, gender predict predict sanctioned to 
  maximum time credit deduction by
  infraction class*/
/**********************************/
/**********************************/
proc sql;
drop table reneephi.z_RQ4;
create table reneephi.z_RQ4 as (
select *
from reneephi.z_final
where cont_calc not in ('LIFE', 'LIFEWOP', 'DEATH') /*Can earn, but only applied in the event of a commutation - see below notes - may be skewed application so omit*/
and total_term < 45 /*remove these because considered life sentence, too*/
AND days_to_take = 'Y' /*at least one day accrued*/
and days_removed ='Y' /*sanctioned to lose days*/
and sufficient_days = 'Y' /*only those who could lose the full range possible*/
)
;
run;

/*OVERALL DESCRIPTIVE VIEW OF WHO LOST MAX CREDITS*/
proc sql;
select miscon_class, maxed_out, count(distinct doc_num) as offenders  /*count(*) as infractions*/
from reneephi.z_RQ4
group by miscon_class, maxed_out;
run;

proc sql;
select miscon_class, male, maxed_out, count(distinct doc_num) as offenders
from reneephi.z_RQ4
group by miscon_class, male, maxed_out;
run;

proc sql;
select miscon_class, race, maxed_out, count(distinct doc_num) as offenders
from reneephi.z_RQ4
group by miscon_class, race, maxed_out;
run;



/*RUN ALL THESE BECAUSE MODEL SUBSETS*/
proc sql;
drop table reneephi.Z_RQ4_B;
create table reneephi.Z_RQ4_B as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,maxed_out
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
	  ,(days/30.42) as mths_to_miscon
	  ,(case when sufficient_days = 'Y' then 1 else 0 end) as suff_day
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ4
where MISCON_CLASS = 'B'
)
;
run;

proc sql;
drop table reneephi.Z_RQ4_A;
create table reneephi.Z_RQ4_A as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,maxed_out
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
	  ,(days/30.42) as mths_to_miscon
	  ,(case when sufficient_days = 'Y' then 1 else 0 end) as suff_day
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ4
where MISCON_CLASS = 'A'
)
;
run;

proc sql;
drop table reneephi.Z_RQ4_X;
create table reneephi.Z_RQ4_X as (
select doc_num, fac_id, miscon_violent, prior_viols, days, multiple_miscon, pct_served_upto_miscon, tot_sanctions 
      ,sex, male, race, black, hispanic, nativeam, white, hsd_least, age_at_miscon, prior_incs_rc, total_term, violent, eighty5, lsi_score, mhl_sysmiss, mhl_cat, exit_mhl
      ,private, maxmed, minimum, community 
      ,maxed_out
      ,(age_at_miscon*age_at_miscon) as age2
      ,log(days) as days_log
      ,log(total_term) as total_term_log
	  ,(days/30.42) as mths_to_miscon
      ,(case when sufficient_days = 'Y' then 1 else 0 end) as suff_day
	  ,SEX||RACE AS SEXRACE
from reneephi.Z_RQ4
where MISCON_CLASS = 'X'
)
;
run;




/*--sample sizes for all subsets:  B, A, X*/
proc sql;
select 'B' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ4_B
UNION ALL
select 'A' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ4_A
UNION ALL
select 'X' as miscon_class, count(*) as incidents, count(distinct doc_num) as persons, count(distinct fac_id) as facility
from reneephi.Z_RQ4_X
run;




/*CROSSTABS FOR DISCRETE: is there a difference in who receives a earned credit sanction by race and gender?*/
proc freq data=reneephi.Z_RQ4_x order=dataset;
   tables maxed_out*sex / NOROW chisq;  /*sex race sexrace*/
   output out=ChiSqData n nmiss pchi lrchi;
run;






/*RQ.4: CLASS Bs*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq4_b n mean std min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white  age_at_miscon hsd_least lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5 pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ maxed_out;
run;


/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq4_b;
 model maxed_out = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;

/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
/*PROC SORT DATA=reneephi.Z_rq4_b;
	BY fac_id;
RUN;

data reneephi.Z_rq4_b;
set reneephi.Z_rq4_b;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;*/

/*2: inmate*/
/*PROC SORT DATA=reneephi.Z_rq4_b;
	BY fac doc_num;
RUN;

data reneephi.Z_rq4_b;
set reneephi.Z_rq4_b;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;*/

/*3: incident*/
/*PROC SORT DATA=reneephi.Z_rq4_b;
	BY fac person;
RUN;

data reneephi.Z_rq4_b;
set reneephi.Z_rq4_b;
record=_n_;
run;

data reneephi.Z_rq4_b;
by doc_num 
if first.doc_num then seq_id=1;
else seq_id+1;
run;



proc sql;
drop table reneephi.z_RQ4b_f;
create table reneephi.z_RQ4b_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq4_b m);
run;*/



/*ASSIGNING IDs*/
/*CROSS-CLASSIFIED*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_rq4_b;
	BY fac_id;
RUN;

data reneephi.Z_rq4_b;
set reneephi.Z_rq4_b;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_rq4_b;
	BY doc_num;
RUN;

data reneephi.Z_rq4_b;
set reneephi.Z_rq4_b;
by doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_rq4_b;
	BY person;
RUN;

data reneephi.Z_rq4_b;
set reneephi.Z_rq4_b;
by person; 
if first.person then record=1;
else record+1;
run;

proc sql;
drop table reneephi.z_RQ4b_f;
create table reneephi.z_RQ4b_f as (
select left(put(m.person,6.)) as person_var
      ,left(put(m.record,6.)) as record_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq4_b m);
run;







/*PREDICTIVE*/
/*MLM 1: unconditional model*/
PROC glimmix DATA=reneephi.z_RQ4b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) =  / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var TYPE=VC;
COVTEST/WALD;
run;

/*MLM 2: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ4b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) =  /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                               / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 3: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ4b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 4: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ4b_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept male  black  hispanic  nativeam  age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM: level 1+2+3 fixed/random efffects*/ 
PROC GLIMMIX DATA=reneephi.z_RQ4b_f METHOD=quad(fastquad qpoints=3) NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
							  /*level 3*/ maxmed  minimum
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;  /*male black hispanic:  this run taking them out to get L1 and L2 fixed only*/
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=500 gconv=1e-4;
COVTEST/WALD;
run;















/*RQ.4: CLASS As*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq4_a n mean std min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white  age_at_miscon hsd_least lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5 pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ maxed_out;
run;

/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq4_a;
 model maxed_out = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;

/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
/*PROC SORT DATA=reneephi.Z_rq4_a;
	BY fac_id;
RUN;

data reneephi.Z_rq4_a;
set reneephi.Z_rq4_a;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
/*PROC SORT DATA=reneephi.Z_rq4_a;
	BY fac doc_num;
RUN;

data reneephi.Z_rq4_a;
set reneephi.Z_rq4_a;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
/*PROC SORT DATA=reneephi.Z_rq4_a;
	BY fac person;
RUN;

data reneephi.Z_rq4_a;
set reneephi.Z_rq4_a;
record=_n_;
run;



proc sql;
drop table reneephi.z_RQ4a_f;
create table reneephi.z_RQ4a_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq4_a m);
run;






/*ASSIGNING IDs*/
/*CROSS-CLASSIFIED*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_rq4_A;
	BY fac_id;
RUN;

data reneephi.Z_rq4_A;
set reneephi.Z_rq4_A;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_rq4_A;
	BY doc_num;
RUN;

data reneephi.Z_rq4_A;
set reneephi.Z_rq4_A;
by doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_rq4_A;
	BY person;
RUN;

data reneephi.Z_rq4_A;
set reneephi.Z_rq4_A;
by person; 
if first.person then record=1;
else record+1;
run;

proc sql;
drop table reneephi.z_RQ4a_f;
create table reneephi.z_RQ4a_f as (
select left(put(m.person,6.)) as person_var
      ,left(put(m.record,6.)) as record_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq4_a m);
run;






/*PREDICTIVE*/
/*MLM 1: unconditional model*/
PROC GLIMMIX DATA=reneephi.z_RQ4a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) =  / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var TYPE=VC;
COVTEST/WALD;
run;

/*MLM 2: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ4a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) =  /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 3: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.z_RQ4a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 4: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.z_RQ4a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept male  black  hispanic  nativeam age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;
run;

/*MLM 5: level 1+2+3 fixed/random efffects*/
PROC GLIMMIX DATA=reneephi.z_RQ4a_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ miscon_violent prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
						      /*level 3*/ maxmed  minimum
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; 
RANDOM intercept / SUBJECT=fac_var TYPE=VC ;  
RANDOM intercept / SUBJECT=person_var TYPE=VC;
COVTEST/WALD;
run;







/*RQ.4: CLASS Xs*/

/*DESCRIPTIVE*/
proc means data=reneephi.Z_rq4_x n mean std min max;
 var /*Level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  white  age_at_miscon hsd_least lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5 pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum  community 
     /*DV*/ maxed_out;
run;

/*collinearity diagnostics*/
proc reg data=reneephi.Z_rq4_x;
 model maxed_out = miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions 
     /*Level 2*/ male  black  hispanic  nativeam  age_at_miscon hsd_least  lsi_score exit_mhl prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon
     /*Level 3*/ maxmed  minimum/  tol vif collin;
run;

/*ASSIGNING IDs*/
/*HIERARCHICAL*/
/*1: facility*/
/*PROC SORT DATA=reneephi.Z_rq4_x;
	BY fac_id;
RUN;

data reneephi.Z_rq4_x;
set reneephi.Z_rq4_x;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
/*PROC SORT DATA=reneephi.Z_rq4_x;
	BY fac doc_num;
RUN;

data reneephi.Z_rq4_x;
set reneephi.Z_rq4_x;
by fac doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
/*PROC SORT DATA=reneephi.Z_rq4_x;
	BY fac person;
RUN;

data reneephi.Z_rq4_x;
set reneephi.Z_rq4_x;
record=_n_;
run;



proc sql;
drop table reneephi.Z_RQ4x_f;
create table reneephi.Z_RQ4x_f as (
select left(put(m.record,6.)) as record_var
      ,left(put(m.person,6.)) as person_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq4_x m);
run;





/*ASSIGNING IDs*/
/*CROSS-CLASSIFIED*/
/*1: facility*/
PROC SORT DATA=reneephi.Z_rq4_x;
	BY fac_id;
RUN;

data reneephi.Z_rq4_x;
set reneephi.Z_rq4_x;
by fac_id;
 retain fac 0;
 if first.fac_id then fac=fac+1;
run;

/*2: inmate*/
PROC SORT DATA=reneephi.Z_rq4_x;
	BY doc_num;
RUN;

data reneephi.Z_rq4_x;
set reneephi.Z_rq4_x;
by doc_num;
 retain person 0;
 if first.doc_num then person=person+1;
run;

/*3: incident*/
PROC SORT DATA=reneephi.Z_rq4_x;
	BY person;
RUN;

data reneephi.Z_rq4_x;
set reneephi.Z_rq4_x;
by person; 
if first.person then record=1;
else record+1;
run;

proc sql;
drop table reneephi.z_RQ4x_f;
create table reneephi.z_RQ4x_f as (
select left(put(m.person,6.)) as person_var
      ,left(put(m.record,6.)) as record_var
      ,left(put(m.fac,6.)) as fac_var
      ,m.*
from reneephi.Z_rq4_x m);
run;



/*PREDICTIVE*/
/*MLM 1: unconditional model*/
PROC GLIMMIX DATA=reneephi.Z_RQ4x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) =  / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var TYPE=VC;
COVTEST/WALD;
run;

/*MLM 2: level 1 fixed effects*/
PROC GLIMMIX DATA=reneephi.Z_RQ4x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) =  /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                               / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
COVTEST/WALD;run;

/*MLM 3: level 1+2 fixed effects*/
PROC GLIMMIX DATA=reneephi.Z_RQ4x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon   tot_sanctions
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=120 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 4: level 1 fixed + Level 2 fixed and random effects*/
PROC GLIMMIX DATA=reneephi.Z_RQ4x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ miscon_violent  prior_viols  mths_to_miscon  multiple_miscon  tot_sanctions
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
						      /*level 3*/ maxmed  minimum
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept male  black  hispanic  nativeam age_at_miscon/  SUBJECT=fac_var TYPE=VC;
RANDOM intercept /  SUBJECT=person_var(fac_var) TYPE=VC;
nloptions technique=congra maxiter=500 gconv=1e-4;
COVTEST/WALD;
run;

/*MLM 5: level 1+2+3 fixed/random efffects*/ 
PROC GLIMMIX DATA=reneephi.Z_RQ4x_f METHOD=rspl NOCLPRINT;
class fac_var person_var;
MODEL maxed_out(event=last) = /*level 1*/ miscon_violent prior_viols mths_to_miscon multiple_miscon tot_sanctions 
                              /*level 2*/ male  black  hispanic  nativeam  age_at_miscon  age2  hsd_least  lsi_score prior_incs_rc  total_term  violent  eighty5  pct_served_upto_miscon /*mhl_cat*/
                              /*level 2 interacts*/ male*black  
                                                    male*hispanic  
                                                    male*nativeam  
                                                    male*age_at_miscon 
                                                    black*age_at_miscon 
                                                    hispanic*age_at_miscon 
                                                    nativeam*age_at_miscon 
                                                    male*black*age_at_miscon  
                                                    male*hispanic*age_at_miscon  
                                                    male*nativeam*age_at_miscon
						      /*level 3*/ maxmed  minimum
                              / CL DIST=binary LINK=logit SOLUTION ddfm=residual; /*for a binary, nonnormal dist.*/
RANDOM intercept /  SUBJECT=fac_var TYPE=VC;  /*male black hispanic:  this run taking them out to get L1 and L2 fixed only*/
RANDOM intercept /  SUBJECT=person_var TYPE=VC;
COVTEST/WALD;
run;










































/*PART 3: HLM*/
/*
Level 1: miscon_class   miscon_violent(Y/N)   priors_rc(Y/N)  days_to_miscon  multiple_miscon  pct_served   tot_sanctions
Level 2: male(Y/N)   black(Y/N)   hispanic(Y/N)   nativeam(Y/N)  hsd_least(Y/N) age_at_miscon   prior_incs_rc(Y/N)   total_term   violent(Y/N)   eighty5(Y/N)   a_lsi_totalscore  mhl_cat  mhl_sysmiss
Level 3: private(Y/N)   maximum(Y/N)   medium(Y/N)   minimum(Y/N)  maxmed  min  comm
DV: maxed_out
*/

/*unconditional model - don't partion by class because all are subject to days and just wanna find out if days were removed*/
proc glimmix data=work.RQ4 NOCLPRINT method=laplace;
class doc_num; 
model maxed_out(event='1') = / cl dist=binary link=logit solution oddsratio; /*for a binary, nonnormal dist.*/
random intercept / solution type=vc subject=doc_num;
covtest/wald;
run;

/*level 1 variables - don't partition by class*/
proc glimmix data=work.RQ4 NOCLPRINT method=laplace;
class doc_num; 
model maxed_out(event='1') = miscon_violent prior_miscons pct_served / cl dist=binary link=logit solution oddsratio; /*for a binary, nonnormal dist.*/
random intercept / solution type=vc subject=doc_num;
covtest/wald;
run;

/*level 1+2 variables - don't partition by class*/
proc glimmix data=work.RQ4 NOCLPRINT method=laplace;
class doc_num miscon_class (REF='B'); 
model maxed_out(event='1') = miscon_class miscon_violent prior_miscons pct_served tot_sanctions
                             male black hispanic nativeam age_log_rq4 prior_incs total_term violent eighty5 
/ cl dist=binary link=logit solution oddsratio; /*for a binary, nonnormal dist.*/
random intercept / solution type=vc subject=doc_num;
covtest/wald;
run;


/**********************************/
/**********************************/
/*SECONDARY ANALYSIS (N=4510; 13868)*/
/**********************************/
/**********************************/

/*base table with stage 1 re-codes*/
proc sql; 
create table misconb2 as (
select m.*
      ,(case 
        when total_term = 0 then 0
	    when total_term >0   and total_term  < 5.0000001 then 5
        when total_term >=5  and total_term < 10.0000001 then 10 
		when total_term >=10 and total_term < 15.0000001 then 15
		when total_term >=15 and total_term < 20.0000001 then 20
		when total_term >=20 and total_term < 25.0000001 then 25
		when total_term >=25 and total_term < 30.0000001 then 30
		when total_term >=30 and total_term < 35.0000001 then 35
		when total_term >=35 and total_term < 40.0000001 then 40
		when total_term >=40 and total_term < 45.0000001 then 45
	   else 99999
	   end) as total_termyr_gp
	  ,(total_term*365.25) as total_term_days
	  ,(total_term*30.42) as total_term_mths
	  ,(prison_exit_date - prison_admit_date) as total_days_served
	  ,(offence_date - prison_admit_date) as tot_days_bf_miscon
	  ,(case 
	     when sentence_adjust_code = 'X2' then 365
	     when sentence_adjust_code = '2X' then 365
	     when sentence_adjust_code = 'X6' then 365
	     when sentence_adjust_code = '6X' then 365
	     when sentence_adjust_code = 'A2' then 180
	     when sentence_adjust_code = '2A' then 120
	     when sentence_adjust_code = '1B' then 60
	     when sentence_adjust_code = 'B2' then 45
        else .
        end) as max_penalty 
	  ,(case
	     when adjust_days=0 then 0
		 when adjust_days>0 and adjust_days<21 then 20
		 when adjust_days>20 and adjust_days<41 then 40
		 when adjust_days>40 and adjust_days<61 then 60
		 when adjust_days>60 and adjust_days<81 then 80
		 when adjust_days>80 and adjust_days<101 then 100
		 when adjust_days>100 and adjust_days<121 then 120
		 when adjust_days>120 and adjust_days<141 then 140
		 when adjust_days>140 and adjust_days<161 then 160
		 when adjust_days>160 and adjust_days<181 then 180
		 when adjust_days>180 and adjust_days<201 then 200
		 when adjust_days>200 and adjust_days<221 then 220
		 when adjust_days>220 and adjust_days<241 then 240
		 when adjust_days>240 and adjust_days<261 then 260
		 when adjust_days>260 and adjust_days<281 then 280
		 when adjust_days>280 and adjust_days<301 then 300
		 when adjust_days>300 and adjust_days<321 then 320
		 when adjust_days>320 and adjust_days<341 then 340
		 when adjust_days>340 and adjust_days<361 then 360
		 when adjust_days>360 and adjust_days<381 then 380
		 when adjust_days>380 and adjust_days<401 then 400
		 when adjust_days>400 then 99999
		 else .
		 end) as adjust_days_gp
      ,(case
	     when adjust_days=0 then 0
		 when adjust_days>0   and adjust_days<51   then 50
		 when adjust_days>50  and adjust_days<101  then 100
		 when adjust_days>100 and adjust_days<151  then 150
		 when adjust_days>150 and adjust_days<201 then 200
		 when adjust_days>200 and adjust_days<251  then 250
		 when adjust_days>250 and adjust_days<301 then 300
		 when adjust_days>300 and adjust_days<351  then 350
		 when adjust_days>350 and adjust_days<401  then 400
		 when adjust_days>400 then 99999
		 else .
		 end) as adjust_days_gp2
from work.MisconductDATA m
where adjust_days is not null)
;
run; 



















/*Note:  
if adjust_days > max_penalty then retained
if paroled then retained ??
if life then removed
if percent served <=0 and >=1 then removed
if race is asian, pacific islander, or other, then removed
*/

/*18250 records:  had misconduct + lost days (0-infinity)*/
Note:  need to remove lifers and then recategorized max penalty.  need to pick back up at narrowing down population
am at the point where i have said x relased, but not all releases are eligible to be included (omit those with no sanction or saction with
penaltiy outside of revoked days).  Need to see if 6622 still holds, becuase it is probably less, especially when i omit those who served 
over 100% of their time or 0% of their time.)   
proc sql; 

/*note:  these folks can accrue only for the pupose of having the sentence commuted.
While under a life sentence—a record of earned credits will be maintained for record keeping purposes. 
Should the sentence be commuted to a specified number of years by the Governor or modified to a specified 
number of years by an appellate court, the recorded credit will be applied*/ 
select *
from work.miscon_final m
where cont_term = 'LIFE'
  or cs_term = 'LIFE';
run; 

/*This is how you do HLM instead of HGLM*/

/*CONTINUOUS OUTCOME*/
/*unconditional model - partitioned by miscon_class*/
proc mixed data=work.RQ3_MB NOCLPRINT covtest method=ml;
class row_number doc_num facname;
model ADJUST_DAYS_RC_LOG_RQ3=/solution ddfm=satterth;
random intercept/sub=doc_num type=vc;
random intercept/sub=facname type=vc;
run;

/*level 1 variables model - partitioned by miscon_class*/
proc mixed data=work.RQ3_FX NOCLPRINT covtest method=ml;
class doc_num facname;
model ADJUST_DAYS_RC_LOG_RQ3= miscon_violent prior_miscons pct_served/solution ddfm=satterth;
random intercept/sub=doc_num type=vc;
random intercept/sub=facname type=vc;
run;

/*level 2 variables model - partitioned by miscon_class*/
proc mixed data=work.RQ3_FX NOCLPRINT covtest method=ml;
class race (REF = 'W') doc_num facname;
model ADJUST_DAYS_RC_LOG_RQ3= race /solution ddfm=satterth;
random intercept/sub=doc_num type=vc;
random intercept/sub=facname type=vc;
run;



/*testing segregation - nothing :  data sets need to be updated*/
PROC GLIMMIX DATA=work.RQ3_MX METHOD=LAPLACE NOCLPRINT;
class doc_num facname;
model mx_seg = miscon_violent prior_miscons pct_served tot_sanctions 
               black hispanic nativeam age_at_miscon prior_incs_rc Total_term violent eighty5 a_lsi_totalscore
               private maximum medium/ DIST=binary LINK=logit SOLUTION CL;
random intercept / SUBJECT=doc_num type=vc SOLUTION CL;
random intercept / SUBJECT=facname type=vc SOLUTION CL;
COVTEST / WALD;
RUN;

proc sql;
drop table rq3_mx;
create table RQ3_MX as (
select *
      ,LOG(adjust_days_rc) AS ADJUST_DAYS_RC_LOG_RQ3
      ,LOG(AGE_AT_MISCON) AS AGE_LOG_RQ3
      ,LOG(PRIOR_INFRACTIONS) AS PRIOR_INFRAC_LOG_RQ3
from work.RQ3
where MALE = 1
AND MISCON_CLASS = 'X'
)
;
run;