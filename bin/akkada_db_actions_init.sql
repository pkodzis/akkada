LOCK TABLES `actions` WRITE;
/*!40000 ALTER TABLE `actions` DISABLE KEYS */;
INSERT INTO `actions` VALUES (1,1,'1800','0','4','','','6','1',1,'mail unreachable state immediately',1,1),(2,1,'1800','300','1','','','2-4','1',1,'mail minor,major and down states after 5 minutes',1,1);
/*!40000 ALTER TABLE `actions` ENABLE KEYS */;
UNLOCK TABLES;

LOCK TABLES `commands` WRITE;
/*!40000 ALTER TABLE `commands` DISABLE KEYS */;
INSERT INTO `commands` VALUES (1,'mail','from => \"akkada\\@localhost\"');
/*!40000 ALTER TABLE `commands` ENABLE KEYS */;
UNLOCK TABLES;

LOCK TABLES `time_periods` WRITE;
/*!40000 ALTER TABLE `time_periods` DISABLE KEYS */;
INSERT INTO `time_periods` VALUES (1,'24x7','0-23','0-23','0-23','0-23','0-23','0-23','0-23'),(2,'24x7 business days','0-23','0-23','0-23','0-23','0-23','',''),(3,'24x7 weekends','','','','','','0-23','0-23'),(4,'mon-fri business hours','9-17','9-17','9-17','9-17','9-17','',''),(5,'mon-fri after business hours','0-9,17-23','0-9,17-23','0-9,17-23','0-9,17-23','0-9,17-23','','');
/*!40000 ALTER TABLE `time_periods` ENABLE KEYS */;
UNLOCK TABLES;

