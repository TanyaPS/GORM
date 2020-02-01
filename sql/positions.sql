ALTER TABLE `locations`
  DROP `position`;
CREATE TABLE `gps`.`positions` (
	`id` INT UNSIGNED NOT NULL AUTO_INCREMENT ,
	`site` CHAR(9) NOT NULL ,
	`position` VARCHAR(60) NOT NULL ,
	`startdate` DATETIME NOT NULL ,
	`enddate` DATETIME NULL ,
	PRIMARY KEY (`id`, `site`)
)
ENGINE = InnoDB;
