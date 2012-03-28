-- phpMyAdmin SQL Dump
-- version 3.2.1
-- http://www.phpmyadmin.net
--
-- Host: mysql-lan-pro
-- Generation Time: Mar 27, 2012 at 10:00 PM
-- Server version: 5.1.39
-- PHP Version: 5.3.10

SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";

--
-- Database: `MTGCommunityAnnot`
--

-- --------------------------------------------------------

--
-- Table structure for table `alleles`
--
-- Creation: Mar 27, 2012 at 09:49 PM
--

CREATE TABLE IF NOT EXISTS `alleles` (
  `allele_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mutant_id` int(10) unsigned NOT NULL,
  `allele_name` varchar(30) COLLATE latin1_general_ci NOT NULL,
  `alt_allele_names` varchar(30) COLLATE latin1_general_ci DEFAULT NULL,
  `reference_lab` mediumtext COLLATE latin1_general_ci NOT NULL,
  `altered_phenotype` mediumtext COLLATE latin1_general_ci NOT NULL,
  PRIMARY KEY (`allele_id`),
  KEY `locus_id` (`mutant_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='Mutant Allele Specific information' AUTO_INCREMENT=21 ;

--
-- RELATIONS FOR TABLE `alleles`:
--   `mutant_id`
--       `mutant_info` -> `mutant_id`
--

-- --------------------------------------------------------

--
-- Table structure for table `alleles_edits`
--
-- Creation: Mar 27, 2012 at 09:50 PM
--

CREATE TABLE IF NOT EXISTS `alleles_edits` (
  `allele_id` int(10) unsigned NOT NULL,
  `mutant_id` int(10) unsigned NOT NULL,
  `edits` mediumtext COLLATE latin1_general_ci NOT NULL,
  PRIMARY KEY (`allele_id`),
  KEY `allele_id` (`allele_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='Mutant Allele Specific information';

-- --------------------------------------------------------

--
-- Table structure for table `family`
--
-- Creation: Mar 27, 2012 at 09:50 PM
--

CREATE TABLE IF NOT EXISTS `family` (
  `family_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(10) unsigned NOT NULL,
  `family_name` varchar(255) COLLATE latin1_general_ci NOT NULL,
  `gene_class_symbol` varchar(30) COLLATE latin1_general_ci NOT NULL,
  `description` mediumtext COLLATE latin1_general_ci,
  `source` mediumtext COLLATE latin1_general_ci,
  `is_public` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`family_id`),
  KEY `user_id` (`user_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='Gene Family information' AUTO_INCREMENT=4 ;

--
-- RELATIONS FOR TABLE `family`:
--   `user_id`
--       `users` -> `user_id`
--

-- --------------------------------------------------------

--
-- Table structure for table `loci`
--
-- Creation: Mar 27, 2012 at 09:50 PM
--

CREATE TABLE IF NOT EXISTS `loci` (
  `locus_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(10) unsigned NOT NULL,
  `family_id` int(10) unsigned NOT NULL,
  `gene_locus` varchar(30) COLLATE latin1_general_ci DEFAULT NULL,
  `orig_func_annotation` mediumtext COLLATE latin1_general_ci,
  `gene_symbol` varchar(30) COLLATE latin1_general_ci NOT NULL,
  `func_annotation` mediumtext COLLATE latin1_general_ci NOT NULL,
  `gb_genomic_acc` varchar(100) COLLATE latin1_general_ci DEFAULT NULL,
  `gb_cdna_acc` varchar(100) COLLATE latin1_general_ci DEFAULT NULL,
  `gb_protein_acc` varchar(100) COLLATE latin1_general_ci DEFAULT NULL,
  `mutant_id` int(10) unsigned DEFAULT NULL,
  `comment` mediumtext COLLATE latin1_general_ci NOT NULL,
  `reference_pub` mediumtext COLLATE latin1_general_ci,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `has_structural_annot` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`locus_id`),
  KEY `user_id` (`user_id`,`family_id`),
  KEY `v2_loci_ibfk_1` (`family_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='Community Annotation for each Medtr locus' AUTO_INCREMENT=32 ;

--
-- RELATIONS FOR TABLE `loci`:
--   `mutant_id`
--       `mutant_info` -> `mutant_id`
--   `family_id`
--       `family` -> `family_id`
--   `user_id`
--       `users` -> `user_id`
--

-- --------------------------------------------------------

--
-- Table structure for table `loci_edits`
--
-- Creation: Mar 27, 2012 at 09:50 PM
--

CREATE TABLE IF NOT EXISTS `loci_edits` (
  `locus_id` int(10) unsigned NOT NULL,
  `user_id` int(10) unsigned NOT NULL,
  `family_id` int(10) unsigned NOT NULL,
  `edits` mediumtext COLLATE latin1_general_ci NOT NULL,
  PRIMARY KEY (`locus_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='Edits made by user to `loci` table';

-- --------------------------------------------------------

--
-- Table structure for table `mutant_class`
--
-- Creation: Mar 27, 2012 at 09:50 PM
--

CREATE TABLE IF NOT EXISTS `mutant_class` (
  `mutant_class_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `symbol` varchar(30) COLLATE latin1_general_ci NOT NULL,
  `symbol_name` mediumtext COLLATE latin1_general_ci NOT NULL,
  PRIMARY KEY (`mutant_class_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='M. truncatula mutant list' AUTO_INCREMENT=29 ;

-- --------------------------------------------------------

--
-- Table structure for table `mutant_class_edits`
--
-- Creation: Mar 27, 2012 at 09:50 PM
--

CREATE TABLE IF NOT EXISTS `mutant_class_edits` (
  `mutant_class_id` int(10) unsigned NOT NULL,
  `symbol` varchar(30) COLLATE latin1_general_ci NOT NULL,
  `symbol_name` mediumtext COLLATE latin1_general_ci NOT NULL,
  PRIMARY KEY (`mutant_class_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='Edits made by user to `mutant_class` table';

-- --------------------------------------------------------

--
-- Table structure for table `mutant_info`
--
-- Creation: Mar 27, 2012 at 09:51 PM
--

CREATE TABLE IF NOT EXISTS `mutant_info` (
  `mutant_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mutant_class_id` int(10) unsigned NOT NULL,
  `symbol` varchar(30) COLLATE latin1_general_ci NOT NULL,
  `phenotype` mediumtext COLLATE latin1_general_ci NOT NULL,
  `mapping_data` mediumtext COLLATE latin1_general_ci NOT NULL,
  `reference_lab` mediumtext COLLATE latin1_general_ci NOT NULL,
  `reference_pub` mediumtext COLLATE latin1_general_ci NOT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`mutant_id`),
  KEY `mutant_class_id` (`mutant_class_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='M. truncatula mutant information' AUTO_INCREMENT=51 ;

--
-- RELATIONS FOR TABLE `mutant_info`:
--   `mutant_class_id`
--       `mutant_class` -> `mutant_class_id`
--

-- --------------------------------------------------------

--
-- Table structure for table `mutant_info_edits`
--
-- Creation: Mar 27, 2012 at 09:51 PM
--

CREATE TABLE IF NOT EXISTS `mutant_info_edits` (
  `mutant_id` int(10) unsigned NOT NULL,
  `edits` mediumtext COLLATE latin1_general_ci NOT NULL,
  PRIMARY KEY (`mutant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_general_ci COMMENT='Edits made by user to `mutant_info` table';

-- --------------------------------------------------------

--
-- Table structure for table `sessions`
--
-- Creation: Mar 27, 2012 at 06:46 PM
-- Last update: Mar 27, 2012 at 06:46 PM
--

CREATE TABLE IF NOT EXISTS `sessions` (
  `id` char(32) NOT NULL,
  `a_session` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='CGI::Session session storage table';

-- --------------------------------------------------------

--
-- Table structure for table `structural_annot`
--
-- Creation: Mar 27, 2012 at 09:51 PM
--

CREATE TABLE IF NOT EXISTS `structural_annot` (
  `sa_id` int(10) NOT NULL AUTO_INCREMENT,
  `locus_id` int(10) unsigned NOT NULL,
  `model` longtext,
  `is_finished` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`sa_id`),
  KEY `locus_id` (`locus_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 COMMENT='Structural Annotation storage' AUTO_INCREMENT=35 ;

--
-- RELATIONS FOR TABLE `structural_annot`:
--   `locus_id`
--       `loci` -> `locus_id`
--

-- --------------------------------------------------------

--
-- Table structure for table `structural_annot_edits`
--
-- Creation: Mar 27, 2012 at 09:51 PM
--

CREATE TABLE IF NOT EXISTS `structural_annot_edits` (
  `sa_id` int(10) NOT NULL,
  `locus_id` int(10) unsigned NOT NULL,
  `model` longtext,
  `is_finished` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`sa_id`),
  KEY `locus_id` (`locus_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COMMENT='Structural Annotation storage';

-- --------------------------------------------------------

--
-- Table structure for table `users`
--
-- Creation: Mar 27, 2012 at 09:51 PM
--

CREATE TABLE IF NOT EXISTS `users` (
  `user_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `username` varchar(20) NOT NULL,
  `salt` char(8) NOT NULL,
  `hash` char(22) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `organization` varchar(100) DEFAULT NULL,
  `url` varchar(100) DEFAULT NULL,
  `photo_file_name` varchar(255) NOT NULL DEFAULT 'default.jpg',
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 COMMENT='Community Annotation users' AUTO_INCREMENT=4 ;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `alleles`
--
ALTER TABLE `alleles`
  ADD CONSTRAINT `alleles_ibfk_1` FOREIGN KEY (`mutant_id`) REFERENCES `mutant_info` (`mutant_id`);

--
-- Constraints for table `family`
--
ALTER TABLE `family`
  ADD CONSTRAINT `family_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`);

--
-- Constraints for table `loci`
--
ALTER TABLE `loci`
  ADD CONSTRAINT `loci_ibfk_1` FOREIGN KEY (`family_id`) REFERENCES `family` (`family_id`),
  ADD CONSTRAINT `loci_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`);

--
-- Constraints for table `mutant_info`
--
ALTER TABLE `mutant_info`
  ADD CONSTRAINT `mutant_info_ibfk_1` FOREIGN KEY (`mutant_class_id`) REFERENCES `mutant_class` (`mutant_class_id`);

--
-- Constraints for table `structural_annot`
--
ALTER TABLE `structural_annot`
  ADD CONSTRAINT `v2_struct_annot_ibfk_1` FOREIGN KEY (`locus_id`) REFERENCES `loci` (`locus_id`);
