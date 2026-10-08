-- MySQL dump 10.13  Distrib 8.4.0, for macos14 (arm64)
/*!50503 SET NAMES utf8mb4 */;
SET @@SESSION.SQL_LOG_BIN= 0;
SET @@GLOBAL.GTID_PURGED=/*!80000 '+'*/ 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:1-5';
DROP TABLE IF EXISTS `wp_posts`;
CREATE TABLE `wp_posts` (
  `ID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `post_title` text COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `post_name` varchar(200) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
INSERT INTO `wp_posts` VALUES (1,'DEFINER=`a`@`b` utf8mb4_0900_ai_ci','one'),(2,'Second','two');
/*!50001 DROP VIEW IF EXISTS `v_posts`*/;
/*!50001 CREATE ALGORITHM=UNDEFINED */ /*!50013 DEFINER=`nouser`@`nohost` SQL SECURITY DEFINER */ /*!50001 VIEW `v_posts` AS select `wp_posts`.`ID` AS `ID` from `wp_posts` */;
