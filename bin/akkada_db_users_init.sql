--
-- Dumping data for table `groups`
--


/*!40000 ALTER TABLE `groups` DISABLE KEYS */;
LOCK TABLES `groups` WRITE;
INSERT INTO `groups` VALUES (1,'master'),(2,'everyone'),(3,'operators');
UNLOCK TABLES;
/*!40000 ALTER TABLE `groups` ENABLE KEYS */;

--
-- Dumping data for table `rights`
--


/*!40000 ALTER TABLE `rights` DISABLE KEYS */;
LOCK TABLES `rights` WRITE;
INSERT INTO `rights` VALUES (0,1,1,1,1,1,1,1,1,1,0),(0,2,1,0,0,0,0,0,0,0,0),(0,3,1,0,0,0,1,0,0,1,0);
UNLOCK TABLES;
/*!40000 ALTER TABLE `rights` ENABLE KEYS */;

--
-- Dumping data for table `users`
--


/*!40000 ALTER TABLE `users` DISABLE KEYS */;
LOCK TABLES `users` WRITE;
INSERT INTO `users` VALUES (1,'yoda','c36a1a0be8f2b05fff7b5cff6bf15973',0,'',''),(2,'operator','4b583376b2767b923c3e1da60d10de59',0,'','');
UNLOCK TABLES;
/*!40000 ALTER TABLE `users` ENABLE KEYS */;

--
-- Dumping data for table `users_2_groups`
--


/*!40000 ALTER TABLE `users_2_groups` DISABLE KEYS */;
LOCK TABLES `users_2_groups` WRITE;
INSERT INTO `users_2_groups` VALUES (1,1),(2,2),(2,3);
UNLOCK TABLES;
/*!40000 ALTER TABLE `users_2_groups` ENABLE KEYS */;


--
-- Dumping data for table `commands`
--

LOCK TABLES `commands` WRITE;
/*!40000 ALTER TABLE `commands` DISABLE KEYS */;
INSERT INTO `commands` VALUES (1,'mail default','from => \"akkada\\@localhost\"','mail'),(2,'gtalk default','username => \"username\\@gmail.com\", password => \"password\"','gtalk');
/*!40000 ALTER TABLE `commands` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `actions`
--

LOCK TABLES `actions` WRITE;
/*!40000 ALTER TABLE `actions` DISABLE KEYS */;
INSERT INTO `actions` VALUES (1,1,'1800','0','4','','','6','1',1,'mail unreachable state immediately',1,1),(2,1,'1800','300','1','','','2-4','1',1,'mail minor,major and down states after 5 minutes',1,1),(3,1,'1800','0','1','','','2-4','1',1,'mail minor,major and down states immediately ',1,1),(4,2,'1800','0','4','','','6','1',1,'GTalk unreachable state immediately',1,1),(5,2,'1800','0','1','','','2-4','1',1,'GTalk minor,major and down states immediately ',1,1),(6,2,'1800','300','1','','','2-4','1',1,'GTalk minor,major and down states after 5 minutes',1,1);
/*!40000 ALTER TABLE `actions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `time_periods`
--

LOCK TABLES `time_periods` WRITE;
/*!40000 ALTER TABLE `time_periods` DISABLE KEYS */;
INSERT INTO `time_periods` VALUES (1,'24x7','0-23','0-23','0-23','0-23','0-23','0-23','0-23'),(2,'24x7 business days','0-23','0-23','0-23','0-23','0-23','',''),(3,'24x7 weekends','','','','','','0-23','0-23'),(4,'mon-fri business hours','9-17','9-17','9-17','9-17','9-17','',''),(5,'mon-fri after business hours','0-9,17-23','0-9,17-23','0-9,17-23','0-9,17-23','0-9,17-23','','');
/*!40000 ALTER TABLE `time_periods` ENABLE KEYS */;
UNLOCK TABLES;


