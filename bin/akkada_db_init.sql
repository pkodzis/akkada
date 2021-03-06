-- MySQL dump 10.10
--
-- Host: localhost    Database: akkada
-- ------------------------------------------------------
-- Server version	5.0.27

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `actions`
--

DROP TABLE IF EXISTS `actions`;
CREATE TABLE `actions` (
  `id_action` bigint(20) unsigned NOT NULL auto_increment,
  `id_command` bigint(20) unsigned NOT NULL default '0',
  `notification_interval` varchar(45) NOT NULL default '',
  `notification_start` varchar(45) NOT NULL default '',
  `notification_stop` varchar(45) NOT NULL default '',
  `service_type` varchar(255) NOT NULL default '',
  `error_messages_like` varchar(255) NOT NULL default '',
  `statuses` varchar(255) NOT NULL default '',
  `notify_recovery` varchar(45) NOT NULL default '',
  `active` smallint(5) unsigned NOT NULL default '1',
  `name` varchar(255) NOT NULL default '',
  `calc` smallint(5) unsigned NOT NULL default '1',
  `inherit` smallint(5) unsigned NOT NULL default '1',
  PRIMARY KEY  (`id_action`),
  UNIQUE KEY `Index_2` (`name`)
) ENGINE=MyISAM AUTO_INCREMENT=8 DEFAULT CHARSET=utf8;

--
-- Table structure for table `cgroups`
--

DROP TABLE IF EXISTS `cgroups`;
CREATE TABLE `cgroups` (
  `id_cgroup` bigint(20) unsigned NOT NULL auto_increment,
  `name` varchar(255) NOT NULL default '',
  PRIMARY KEY  (`id_cgroup`)
) ENGINE=MyISAM AUTO_INCREMENT=4 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `cgroups`
--

LOCK TABLES `cgroups` WRITE;
/*!40000 ALTER TABLE `cgroups` DISABLE KEYS */;
/*!40000 ALTER TABLE `cgroups` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `commands`
--

DROP TABLE IF EXISTS `commands`;
CREATE TABLE `commands` (
  `id_command` bigint(20) unsigned NOT NULL auto_increment,
  `name` varchar(45) NOT NULL,
  `command` varchar(255) NOT NULL,
  `module` varchar(255) NOT NULL,
  PRIMARY KEY  (`id_command`)
) ENGINE=MyISAM AUTO_INCREMENT=6 DEFAULT CHARSET=utf8;

--
-- Table structure for table `comments`
--

DROP TABLE IF EXISTS `comments`;
CREATE TABLE `comments` (
  `id_comment` bigint(20) unsigned NOT NULL auto_increment,
  `id_entity` bigint(20) unsigned NOT NULL default '0',
  `msg` text NOT NULL,
  `id_user` bigint(20) unsigned NOT NULL default '0',
  `timestamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`id_comment`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `comments`
--

LOCK TABLES `comments` WRITE;
/*!40000 ALTER TABLE `comments` DISABLE KEYS */;
/*!40000 ALTER TABLE `comments` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `contacts`
--

DROP TABLE IF EXISTS `contacts`;
CREATE TABLE `contacts` (
  `id_contact` bigint(20) unsigned NOT NULL auto_increment,
  `name` varchar(255) NOT NULL default '',
  `email` varchar(255) default NULL,
  `phone` varchar(255) default NULL,
  `active` int(10) unsigned NOT NULL default '1',
  `company` varchar(255) default NULL,
  `alias` varchar(45) NOT NULL,
  `other` varchar(255) default NULL,
  PRIMARY KEY  USING BTREE (`id_contact`,`name`,`alias`),
  UNIQUE KEY `Index_2` (`name`)
) ENGINE=MyISAM AUTO_INCREMENT=4 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `contacts`
--

LOCK TABLES `contacts` WRITE;
/*!40000 ALTER TABLE `contacts` DISABLE KEYS */;
/*!40000 ALTER TABLE `contacts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `contacts_2_cgroups`
--

DROP TABLE IF EXISTS `contacts_2_cgroups`;
CREATE TABLE `contacts_2_cgroups` (
  `id_contact` bigint(20) unsigned NOT NULL default '0',
  `id_cgroup` bigint(20) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id_contact`,`id_cgroup`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `contacts_2_cgroups`
--

LOCK TABLES `contacts_2_cgroups` WRITE;
/*!40000 ALTER TABLE `contacts_2_cgroups` DISABLE KEYS */;
/*!40000 ALTER TABLE `contacts_2_cgroups` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `discover`
--

DROP TABLE IF EXISTS `discover`;
CREATE TABLE `discover` (
  `id_probe_type` bigint(20) unsigned NOT NULL default '0',
  `id_entity` bigint(20) unsigned NOT NULL default '0',
  `timestamp` timestamp NOT NULL default '0000-00-00 00:00:00',
  `id_user` bigint(20) unsigned NOT NULL default '0',
  `ip` varchar(45) NOT NULL default '',
  PRIMARY KEY  (`id_probe_type`,`id_entity`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `discover`
--

LOCK TABLES `discover` WRITE;
/*!40000 ALTER TABLE `discover` DISABLE KEYS */;
/*!40000 ALTER TABLE `discover` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `entities`
--

DROP TABLE IF EXISTS `entities`;
CREATE TABLE `entities` (
  `id_entity` bigint(20) NOT NULL auto_increment,
  `name` varchar(255) default NULL,
  `status` int(11) NOT NULL default '124',
  `check_period` int(11) NOT NULL default '60',
  `id_probe_type` int(11) NOT NULL default '0',
  `probe_pid` int(11) default NULL,
  `status_weight` smallint(6) NOT NULL default '1',
  `errmsg` varchar(255) default NULL,
  `status_last_change` datetime NOT NULL default '0000-00-00 00:00:00',
  `discover_period` int(11) NOT NULL default '36000',
  `description_static` varchar(255) NOT NULL default '',
  `description_dynamic` varchar(255) default NULL,
  `deleted` int(11) NOT NULL default '0',
  `monitor` int(11) NOT NULL default '1',
  `err_approved_at` bigint(20) default '0',
  `err_approved_by` bigint(20) default '0',
  `err_approved_ip` varchar(45) default NULL,
  `flap_monitor` varchar(16) NOT NULL default '0',
  `flap` bigint(20) NOT NULL default '0',
  `flap_status` int(11) NOT NULL default '127',
  `flap_errmsg` varchar(255) default NULL,
  `flap_count` bigint(20) unsigned NOT NULL default '0',
  `status_last_change_prev` bigint(20) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id_entity`),
  KEY `idx_id_entity` (`id_entity`)
) ENGINE=MyISAM AUTO_INCREMENT=4231 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `entities`
--

LOCK TABLES `entities` WRITE;
/*!40000 ALTER TABLE `entities` DISABLE KEYS */;
/*!40000 ALTER TABLE `entities` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `entities_2_actions`
--

DROP TABLE IF EXISTS `entities_2_actions`;
CREATE TABLE `entities_2_actions` (
  `id_entity` bigint(20) unsigned NOT NULL default '0',
  `id_action` bigint(20) unsigned NOT NULL default '0',
  `id_cgroup` bigint(20) unsigned NOT NULL default '0',
  `id_time_period` bigint(20) unsigned NOT NULL default '0',
  `id_e2a` bigint(20) unsigned NOT NULL auto_increment,
  PRIMARY KEY  (`id_e2a`),
  UNIQUE KEY `Index_2` (`id_entity`,`id_action`,`id_cgroup`,`id_time_period`)
) ENGINE=MyISAM AUTO_INCREMENT=48 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `entities_2_actions`
--

LOCK TABLES `entities_2_actions` WRITE;
/*!40000 ALTER TABLE `entities_2_actions` DISABLE KEYS */;
/*!40000 ALTER TABLE `entities_2_actions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `entities_2_cgroups`
--

DROP TABLE IF EXISTS `entities_2_cgroups`;
CREATE TABLE `entities_2_cgroups` (
  `id_entity` bigint(20) unsigned NOT NULL default '0',
  `id_cgroup` bigint(20) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id_entity`,`id_cgroup`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `entities_2_cgroups`
--

LOCK TABLES `entities_2_cgroups` WRITE;
/*!40000 ALTER TABLE `entities_2_cgroups` DISABLE KEYS */;
/*!40000 ALTER TABLE `entities_2_cgroups` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `entities_2_parameters`
--

DROP TABLE IF EXISTS `entities_2_parameters`;
CREATE TABLE `entities_2_parameters` (
  `id_entity` bigint(20) NOT NULL default '0',
  `id_parameter` bigint(20) NOT NULL default '0',
  `value` text NOT NULL,
  PRIMARY KEY  (`id_entity`,`id_parameter`),
  KEY `FK_entities_2_parameters_2` (`id_parameter`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `entities_2_parameters`
--

LOCK TABLES `entities_2_parameters` WRITE;
/*!40000 ALTER TABLE `entities_2_parameters` DISABLE KEYS */;
/*!40000 ALTER TABLE `entities_2_parameters` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `entities_2_views`
--

DROP TABLE IF EXISTS `entities_2_views`;
CREATE TABLE `entities_2_views` (
  `id_view` bigint(20) unsigned NOT NULL default '0',
  `id_entity` bigint(20) unsigned NOT NULL default '0',
  `view_order` smallint(5) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id_view`,`id_entity`),
  UNIQUE KEY `Index_2` USING HASH (`view_order`,`id_view`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `entities_2_views`
--

LOCK TABLES `entities_2_views` WRITE;
/*!40000 ALTER TABLE `entities_2_views` DISABLE KEYS */;
/*!40000 ALTER TABLE `entities_2_views` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `force_test`
--

DROP TABLE IF EXISTS `force_test`;
CREATE TABLE `force_test` (
  `id_entity` bigint(20) unsigned NOT NULL auto_increment,
  `timestamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  `id_user` bigint(20) unsigned NOT NULL default '0',
  `ip` varchar(45) NOT NULL default '',
  PRIMARY KEY  (`id_entity`)
) ENGINE=MyISAM AUTO_INCREMENT=4096 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `force_test`
--

LOCK TABLES `force_test` WRITE;
/*!40000 ALTER TABLE `force_test` DISABLE KEYS */;
/*!40000 ALTER TABLE `force_test` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `groups`
--

DROP TABLE IF EXISTS `groups`;
CREATE TABLE `groups` (
  `id_group` bigint(20) unsigned NOT NULL auto_increment,
  `name` varchar(45) NOT NULL default '',
  PRIMARY KEY  (`id_group`),
  UNIQUE KEY `Index_2` (`name`)
) ENGINE=MyISAM AUTO_INCREMENT=4 DEFAULT CHARSET=utf8;

--
-- Table structure for table `history24`
--

DROP TABLE IF EXISTS `history24`;
CREATE TABLE `history24` (
  `id` bigint(20) unsigned NOT NULL auto_increment,
  `id_entity` bigint(20) unsigned NOT NULL default '0',
  `status_old` int(10) unsigned NOT NULL default '0',
  `status_new` int(10) unsigned NOT NULL default '0',
  `errmsg` varchar(255) default NULL,
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  `err_approved_at` bigint(20) default '0',
  `err_approved_by` bigint(20) default '0',
  `err_approved_ip` varchar(44) default NULL,
  `flap` int(11) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `Index_2` (`id_entity`),
  KEY `Index_3` (`time`)
) ENGINE=MyISAM AUTO_INCREMENT=30136 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `history24`
--

LOCK TABLES `history24` WRITE;
/*!40000 ALTER TABLE `history24` DISABLE KEYS */;
/*!40000 ALTER TABLE `history24` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `links`
--

DROP TABLE IF EXISTS `links`;
CREATE TABLE `links` (
  `id_parent` bigint(20) NOT NULL default '0',
  `id_child` bigint(20) NOT NULL default '0',
  PRIMARY KEY  (`id_child`),
  KEY `FK_links_1` (`id_parent`),
  KEY `FK_links_2` (`id_child`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `links`
--

LOCK TABLES `links` WRITE;
/*!40000 ALTER TABLE `links` DISABLE KEYS */;
/*!40000 ALTER TABLE `links` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `parameters`
--

DROP TABLE IF EXISTS `parameters`;
CREATE TABLE `parameters` (
  `id_parameter` bigint(20) NOT NULL auto_increment,
  `name` varchar(128) NOT NULL default '',
  `description` varchar(255) default NULL,
  `ro` smallint(5) unsigned default '0',
  PRIMARY KEY  (`id_parameter`)
) ENGINE=MyISAM AUTO_INCREMENT=173 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `parameters`
--

LOCK TABLES `parameters` WRITE;
/*!40000 ALTER TABLE `parameters` DISABLE KEYS */;
INSERT INTO `parameters` VALUES (1,'ip','ip address',0),(2,'snmp_community_ro','snmp community read-only string',0),(3,'timeout','',0),(4,'nic_bandwidth','nadpisuje parametr ifSpeed zwracany przez snmp',0),(5,'port','',0),(6,'index','',0),(7,'nic_port_slot','',0),(10,'threshold_medium','',0),(11,'threshold_high','',0),(12,'nic_port_index','',0),(13,'snmp_version','',0),(15,'vendor','',0),(16,'function','',0),(17,'oids_disabled','',0),(19,'snmp_split_request','',0),(20,'nic_ifOperStatus_ignore','wylacza sprawdzanie ifOperStatus',0),(21,'nic_errors_ignore','wylacza sprawdzanie errorow na interfejsach',0),(22,'nic_speed_check_disable','wylacza sprawdzanie utylizacji interfejsu',0),(23,'nic_bandwidth_aggregate','wlacza sprawdzanie utylizacji sumarycznej in/out',0),(24,'cpu_type','',0),(25,'cpu_count','',0),(26,'cpu_host_resources_utilization_aggregate','wlacza sprawdzanie utylizacji sumarycznej CPU jesli jest wiecej niz 1 CPU',0),(28,'cpu_ucd_la_1_threshhold','nadpisuje laConfig z UCD /etc/snmp/snmpd.conf',0),(29,'cpu_ucd_la_5_threshhold','nadpisuje laConfig z UCD /etc/snmp/snmpd.conf',0),(30,'cpu_ucd_la_15_threshhold','nadpisuje laConfig z UCD /etc/snmp/snmpd.conf',0),(31,'tcp_generic_script','skrypt postaci: wait::xxx||send::yyy %NL% zamiast \\n',0),(32,'cpu_ucd_utilization_aggregate',NULL,0),(33,'hdd_type',NULL,0),(34,'hdd_threshold_bytes_mode','byte or percent; default percent',0),(35,'hdd_threshold_minimum_bytes','minimum disk free kBytes if hdd_threshold_mode byte',0),(36,'ram_threshold_bytes_mode',NULL,0),(37,'ram_threshold_minimum_bytes',NULL,0),(38,'ram_type',NULL,0),(39,'ram_disable_memory_full_alarm_real','used in: ucd',0),(40,'ram_disable_memory_full_alarm_swap','used in: ucd',0),(41,'ram_disable_memory_full_alarm_total','used in: ucd, cisco',0),(42,'nic_ambiguous_ifDescr',NULL,0),(43,'ucd_process_min',NULL,0),(44,'ucd_process_max',NULL,0),(45,'ucd_ext_min',NULL,0),(46,'ucd_ext_max',NULL,0),(47,'ucd_ext_expect',NULL,0),(48,'ssl_generic_script',NULL,0),(49,'attempts_retry_interval',NULL,0),(50,'attempts_current_count',NULL,1),(51,'attempts_max_count',NULL,0),(52,'flaps_alarm_count',NULL,0),(54,'cisco_css_service_stop_warning_suspended_state',NULL,0),(55,'cisco_css_content_stop_warning_suspended_state',NULL,0),(56,'cisco_css_content_index_2',NULL,0),(57,'cisco_css_content_index_1',NULL,0),(60,'cisco_css_content_stop_warning_high_load',NULL,0),(61,'cisco_css_service_stop_warning_high_load',NULL,0),(62,'dns_server_hostname',NULL,0),(63,'dns_query_query','hostname: e.g. www.wp.pl',0),(64,'dns_query_record_type','A|CNAME|MX|PTR itd',0),(65,'dns_query_expected_value',NULL,0),(66,'dns_query_field','name|address -> see Net::DNS man',0),(67,'softax_ping_version',NULL,0),(68,'softax_ping_protocol','http|ssl',0),(69,'softax_ping_port',NULL,0),(70,'softax_ima_port',NULL,0),(71,'softax_ima_community',NULL,0),(76,'host_resources_process_min',NULL,0),(77,'host_resources_process_max',NULL,0),(78,'route_next_hop',NULL,0),(79,'ucd_ext_bad',NULL,0),(80,'ucd_ext_data_type',NULL,0),(82,'flaps_disable_monitor',NULL,0),(83,'windows_service_hex',NULL,0),(84,'host_resources_process_cpu_time_max',NULL,0),(85,'host_resources_process_memory_max',NULL,0),(86,'tcp_generic_service_name',NULL,0),(87,'ssl_generic_service_name',NULL,0),(88,'cisco_css_service_stop_warning_down_state',NULL,0),(89,'cisco_css_service_stop_warning_high_average_load',NULL,0),(90,'cisco_css_service_stop_warning_high_long_load',NULL,0),(91,'cisco_css_service_stop_warning_high_short_load',NULL,0),(92,'snmp_authpassword',NULL,0),(93,'snmp_user',NULL,0),(94,'snmp_timeout',NULL,0),(95,'snmp_retry',NULL,0),(96,'snmp_authprotocol',NULL,0),(97,'snmp_privprotocol',NULL,0),(98,'snmp_privpassword',NULL,0),(153,'snmp_generic_text_test_disable',NULL,0),(152,'threshold_too_low',NULL,0),(101,'host_resources_process_ignore_invalid_state',NULL,0),(102,'nic_ip',NULL,0),(103,'nic_ip_icmp_check_disable',NULL,0),(104,'nic_ip_icmp_check_max_delay_threshold',NULL,0),(105,'nic_ip_icmp_check_lost_threshold',NULL,0),(106,'host_resources_process_path_mode',NULL,0),(107,'dont_discover',NULL,0),(109,'cpu_stop_warning_high_utilization',NULL,0),(110,'disable_error_message_change_log',NULL,0),(111,'bgp_peer_state_ignore',NULL,0),(112,'bgp_peer_errors_ignore',NULL,0),(135,'tcpip_tcpInErrs_threshold_units',NULL,0),(134,'tcpip_icmpOutErrors_threshold_percent',NULL,0),(133,'tcpip_icmpOutErrors_threshold_units',NULL,0),(132,'tcpip_icmpInErrors_threshold_percent',NULL,0),(131,'tcpip_icmpInErrors_threshold_units',NULL,0),(130,'tcpip_threshold_units',NULL,0),(129,'tcpip_threshold_percent',NULL,0),(146,'availability_check_disable',NULL,0),(136,'tcpip_tcpInErrs_threshold_percent',NULL,0),(137,'tcpip_udpInErrors_threshold_units',NULL,0),(138,'tcpip_udpInErrors_threshold_percent',NULL,0),(139,'tcpip_ipInHdrErrors_threshold_units',NULL,0),(140,'tcpip_ipInAddrErrors_threshold_units',NULL,0),(141,'tcpip_ipReasmFails_threshold_units',NULL,0),(142,'tcpip_ipFragFails_threshold_units',NULL,0),(143,'tcpip_ipInHdrErrors_threshold_percent',NULL,0),(144,'tcpip_ipInAddrErrors_threshold_percent',NULL,0),(164,'cisco_pix_ipsec_username',NULL,0),(147,'ianaiftype',NULL,0),(148,'softax_ima_start_alarm_warnings',NULL,0),(149,'softax_ima_stop_alarm_errors',NULL,0),(150,'snmp_generic_definition_name',NULL,1),(154,'stop_discover',NULL,0),(155,'windows_service_oid_name',NULL,0),(156,'hdd_stop_raise_inode_alarms',NULL,0),(157,'snmp_instance',NULL,1),(158,'snmp_port',NULL,0),(159,'nic_ifOperStatus_invert',NULL,0),(160,'nic_ifOperStatus_invert_msg',NULL,0),(161,'windows_service_invert',NULL,0),(162,'windows_service_invert_msg',NULL,0),(165,'cisco_pix_ipsec_password',NULL,0),(166,'cisco_pix_ipsec_enable',NULL,0),(167,'cisco_pix_ipsec_names',NULL,0),(168,'cisco_pix_ipsec_alarm_down',NULL,0),(169,'cisco_pix_ipsec_dont_alarm_wrong_state',NULL,0),(170,'nic_ifOperStatus_interpret_dormant_down',NULL,0),(171,'ip_forwarding',NULL,0),(172,'ip_addresses',NULL,1);
/*!40000 ALTER TABLE `parameters` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `rights`
--

DROP TABLE IF EXISTS `rights`;
CREATE TABLE `rights` (
  `id_entity` bigint(20) unsigned NOT NULL default '0',
  `id_group` bigint(20) unsigned NOT NULL default '0',
  `vie` smallint(5) unsigned NOT NULL default '1',
  `mdy` smallint(5) unsigned NOT NULL default '0',
  `cre` smallint(5) unsigned NOT NULL default '0',
  `del` smallint(5) unsigned NOT NULL default '0',
  `com` smallint(5) unsigned NOT NULL default '1',
  `vio` smallint(5) unsigned NOT NULL default '1',
  `cmo` smallint(5) unsigned NOT NULL default '0',
  `ack` smallint(5) unsigned NOT NULL default '0',
  `disabled` smallint(5) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id_entity`,`id_group`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Table structure for table `statuses`
--

DROP TABLE IF EXISTS `statuses`;
CREATE TABLE `statuses` (
  `id_entity` bigint(20) NOT NULL auto_increment,
  `status` int(11) NOT NULL default '124',
  `last_change` datetime NOT NULL default '0000-00-00 00:00:00',
  `status_weight` smallint(6) NOT NULL default '1',
  `last_change_prev` bigint(20) NOT NULL default '0',
  PRIMARY KEY  (`id_entity`)
) ENGINE=MyISAM AUTO_INCREMENT=4228 DEFAULT CHARSET=utf8;

--
-- Dumping data for table `statuses`
--

LOCK TABLES `statuses` WRITE;
/*!40000 ALTER TABLE `statuses` DISABLE KEYS */;
/*!40000 ALTER TABLE `statuses` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `time_periods`
--

DROP TABLE IF EXISTS `time_periods`;
CREATE TABLE `time_periods` (
  `id_time_period` int(10) unsigned NOT NULL auto_increment,
  `name` varchar(45) NOT NULL,
  `monday` varchar(45) NOT NULL,
  `tuesday` varchar(45) NOT NULL,
  `wednesday` varchar(45) NOT NULL,
  `thursday` varchar(45) NOT NULL,
  `friday` varchar(45) NOT NULL,
  `saturday` varchar(45) NOT NULL,
  `sunday` varchar(45) NOT NULL,
  PRIMARY KEY  (`id_time_period`)
) ENGINE=MyISAM AUTO_INCREMENT=6 DEFAULT CHARSET=utf8;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `id_user` bigint(20) unsigned NOT NULL auto_increment,
  `username` varchar(45) NOT NULL default '',
  `password` varchar(45) NOT NULL default '',
  `locked` smallint(5) unsigned NOT NULL default '0',
  `context` text,
  `dashboard` varchar(255) NOT NULL,
  PRIMARY KEY  (`id_user`),
  UNIQUE KEY `Index_2` (`username`)
) ENGINE=MyISAM AUTO_INCREMENT=3 DEFAULT CHARSET=utf8;

--
-- Table structure for table `users_2_groups`
--

DROP TABLE IF EXISTS `users_2_groups`;
CREATE TABLE `users_2_groups` (
  `id_user` bigint(20) unsigned NOT NULL default '0',
  `id_group` bigint(20) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id_user`,`id_group`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Table structure for table `views`
--

DROP TABLE IF EXISTS `views`;
CREATE TABLE `views` (
  `id_view` bigint(20) unsigned NOT NULL auto_increment,
  `name` varchar(255) NOT NULL default '',
  `status` bigint(20) unsigned NOT NULL default '124',
  `function` varchar(255) NOT NULL default '',
  `last_change` datetime NOT NULL default '0000-00-00 00:00:00',
  `id_view_type` bigint(20) unsigned NOT NULL default '0',
  `data` varchar(255) default NULL,
  PRIMARY KEY  (`id_view`,`name`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `views`
--

LOCK TABLES `views` WRITE;
/*!40000 ALTER TABLE `views` DISABLE KEYS */;
/*!40000 ALTER TABLE `views` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2008-06-13  8:17:24
