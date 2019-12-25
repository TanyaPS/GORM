-- Generation Time: Dec 25, 2019 at 02:42 PM
-- Server version: 5.5.64-MariaDB
-- PHP Version: 7.3.13

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `gps`
--

-- --------------------------------------------------------

--
-- Table structure for table `antennas`
--

CREATE TABLE IF NOT EXISTS `antennas` (
  `id` int(11) NOT NULL,
  `site` char(9) COLLATE utf8_unicode_ci NOT NULL,
  `anttype` varchar(20) COLLATE utf8_unicode_ci NOT NULL,
  `antsn` varchar(20) COLLATE utf8_unicode_ci NOT NULL,
  `antdelta` varchar(42) COLLATE utf8_unicode_ci NOT NULL DEFAULT '0,0,0',
  `startdate` datetime NOT NULL,
  `enddate` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `datagaps`
--

CREATE TABLE IF NOT EXISTS `datagaps` (
  `id` int(10) unsigned NOT NULL,
  `site` char(9) COLLATE utf8_unicode_ci NOT NULL,
  `year` smallint(4) unsigned NOT NULL,
  `doy` smallint(3) unsigned NOT NULL,
  `hour` char(1) COLLATE utf8_unicode_ci NOT NULL,
  `jday` mediumint(7) unsigned NOT NULL DEFAULT '0',
  `gapno` smallint(5) unsigned NOT NULL,
  `gapstart` datetime NOT NULL,
  `gapend` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gpssums`
--

CREATE TABLE IF NOT EXISTS `gpssums` (
  `id` int(10) unsigned NOT NULL,
  `site` char(9) COLLATE utf8_unicode_ci NOT NULL,
  `year` smallint(4) unsigned NOT NULL,
  `doy` smallint(3) NOT NULL,
  `hour` char(1) COLLATE utf8_unicode_ci NOT NULL,
  `jday` mediumint(7) unsigned NOT NULL DEFAULT '0',
  `quality` tinyint(3) unsigned NOT NULL DEFAULT '0' COMMENT 'QC',
  `ngaps` mediumint(5) unsigned NOT NULL DEFAULT '0',
  `ts` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `sumfile` blob
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `localdirs`
--

CREATE TABLE IF NOT EXISTS `localdirs` (
  `name` varchar(32) COLLATE utf8_unicode_ci NOT NULL,
  `path` varchar(256) COLLATE utf8_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `locations`
--

CREATE TABLE IF NOT EXISTS `locations` (
  `site` char(9) COLLATE utf8_unicode_ci NOT NULL,
  `shortname` char(4) COLLATE utf8_unicode_ci NOT NULL,
  `freq` enum('H','D') COLLATE utf8_unicode_ci NOT NULL DEFAULT 'H',
  `obsint` tinyint(3) unsigned NOT NULL DEFAULT '1',
  `markernumber` varchar(60) COLLATE utf8_unicode_ci DEFAULT NULL,
  `markertype` enum('GEODETIC','NON_GEODETIC','NON_PHYSICAL','SPACEBORNE','GROUND_CRAFT','WATER_CRAFT','AIRBORNE','FIXED_BUOY','FLOATING_BUOY','FLOATING_ICE','GLACIER','BALLISTIC','ANIMAL','HUMAN') COLLATE utf8_unicode_ci DEFAULT 'GEODETIC',
  `position` varchar(40) COLLATE utf8_unicode_ci DEFAULT NULL,
  `observer` varchar(20) COLLATE utf8_unicode_ci NOT NULL DEFAULT 'SDFE',
  `agency` varchar(24) COLLATE utf8_unicode_ci NOT NULL DEFAULT 'SDFE',
  `ts` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `active` tinyint(1) unsigned NOT NULL DEFAULT '1'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `receivers`
--

CREATE TABLE IF NOT EXISTS `receivers` (
  `id` int(11) NOT NULL,
  `site` char(9) COLLATE utf8_unicode_ci NOT NULL,
  `recsn` varchar(20) COLLATE utf8_unicode_ci NOT NULL,
  `rectype` varchar(20) COLLATE utf8_unicode_ci NOT NULL,
  `firmware` varchar(24) COLLATE utf8_unicode_ci NOT NULL,
  `startdate` datetime NOT NULL,
  `enddate` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `rinexdist`
--

CREATE TABLE IF NOT EXISTS `rinexdist` (
  `id` int(10) unsigned NOT NULL,
  `site` char(9) COLLATE utf8_unicode_ci NOT NULL,
  `freq` enum('D','H') COLLATE utf8_unicode_ci NOT NULL DEFAULT 'D' COMMENT 'D for daily, H for hourly',
  `filetype` enum('Obs','Nav','Arc','Raw','Met','Sum') COLLATE utf8_unicode_ci NOT NULL DEFAULT 'Obs',
  `obsint` tinyint(3) unsigned NOT NULL,
  `localdir` varchar(32) COLLATE utf8_unicode_ci NOT NULL,
  `active` tinyint(1) unsigned NOT NULL DEFAULT '1'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `uploaddest`
--

CREATE TABLE IF NOT EXISTS `uploaddest` (
  `id` int(10) unsigned NOT NULL,
  `name` varchar(25) COLLATE utf8_unicode_ci NOT NULL,
  `protocol` enum('ftp','sftp') COLLATE utf8_unicode_ci NOT NULL DEFAULT 'ftp',
  `host` varchar(64) COLLATE utf8_unicode_ci NOT NULL,
  `user` varchar(32) COLLATE utf8_unicode_ci NOT NULL,
  `pass` varchar(32) COLLATE utf8_unicode_ci DEFAULT NULL,
  `privatekey` varchar(64) COLLATE utf8_unicode_ci DEFAULT NULL,
  `localdir` varchar(32) COLLATE utf8_unicode_ci NOT NULL,
  `remotedir` varchar(128) COLLATE utf8_unicode_ci NOT NULL,
  `active` tinyint(1) unsigned NOT NULL DEFAULT '1',
  `ts` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `antennas`
--
ALTER TABLE `antennas`
  ADD PRIMARY KEY (`id`),
  ADD KEY `antennas_site` (`site`) USING BTREE;

--
-- Indexes for table `datagaps`
--
ALTER TABLE `datagaps`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `datagaps_gaps` (`site`,`year`,`doy`,`hour`,`gapno`) USING BTREE,
  ADD KEY `datagaps_jday` (`site`,`jday`,`hour`);

--
-- Indexes for table `gpssums`
--
ALTER TABLE `gpssums`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `gpssums_site_idx` (`site`,`year`,`doy`,`hour`),
  ADD UNIQUE KEY `gpssums_jday_idx` (`site`,`jday`,`hour`);

--
-- Indexes for table `localdirs`
--
ALTER TABLE `localdirs`
  ADD PRIMARY KEY (`name`);

--
-- Indexes for table `locations`
--
ALTER TABLE `locations`
  ADD PRIMARY KEY (`site`),
  ADD UNIQUE KEY `shortname` (`shortname`);

--
-- Indexes for table `receivers`
--
ALTER TABLE `receivers`
  ADD PRIMARY KEY (`id`),
  ADD KEY `receivers_site` (`site`) USING BTREE;

--
-- Indexes for table `rinexdist`
--
ALTER TABLE `rinexdist`
  ADD PRIMARY KEY (`id`),
  ADD KEY `rinexdist_site` (`site`,`freq`);

--
-- Indexes for table `uploaddest`
--
ALTER TABLE `uploaddest`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `antennas`
--
ALTER TABLE `antennas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `datagaps`
--
ALTER TABLE `datagaps`
  MODIFY `id` int(10) unsigned NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `gpssums`
--
ALTER TABLE `gpssums`
  MODIFY `id` int(10) unsigned NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `receivers`
--
ALTER TABLE `receivers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `rinexdist`
--
ALTER TABLE `rinexdist`
  MODIFY `id` int(10) unsigned NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `uploaddest`
--
ALTER TABLE `uploaddest`
  MODIFY `id` int(10) unsigned NOT NULL AUTO_INCREMENT;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
