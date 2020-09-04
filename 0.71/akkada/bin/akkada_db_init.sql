/*!40000 ALTER TABLE `groups` DISABLE KEYS */;
LOCK TABLES `groups` WRITE;
INSERT INTO `groups` VALUES (1,'master'),(2,'everyone'),(3,'operators');
UNLOCK TABLES;
/*!40000 ALTER TABLE `groups` ENABLE KEYS */;

--

	
/*!40000 ALTER TABLE `rights` DISABLE KEYS */;
LOCK TABLES `rights` WRITE;
INSERT INTO `rights` VALUES (0,1,1,1,1,1,1,1,1,1,0),(0,2,1,0,0,0,0,0,0,0,0),(0,3,1,0,0,0,1,0,0,1,0);
UNLOCK TABLES;
/*!40000 ALTER TABLE `rights` ENABLE KEYS */;


/*!40000 ALTER TABLE `users` DISABLE KEYS */;
LOCK TABLES `users` WRITE;
INSERT INTO `users` VALUES (1,'yoda','c36a1a0be8f2b05fff7b5cff6bf15973',0,''),(2,'operator','4b583376b2767b923c3e1da60d10de59',0,'');
UNLOCK TABLES;
/*!40000 ALTER TABLE `users` ENABLE KEYS */;


/*!40000 ALTER TABLE `users_2_groups` DISABLE KEYS */;
LOCK TABLES `users_2_groups` WRITE;
INSERT INTO `users_2_groups` VALUES (1,1),(2,2),(2,3);
UNLOCK TABLES;
/*!40000 ALTER TABLE `users_2_groups` ENABLE KEYS */;

