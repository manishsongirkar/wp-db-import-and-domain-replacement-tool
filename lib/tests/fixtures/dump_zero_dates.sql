-- Dump from a tool that does not set sql_mode: zero dates in a column default and in rows (issue #24)
/*!40101 SET NAMES utf8mb4 */;
DROP TABLE IF EXISTS `wp_posts`;
CREATE TABLE `wp_posts` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `post_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_gmt` date DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
INSERT INTO `wp_posts` VALUES (1,'Hello','0000-00-00 00:00:00','0000-00-00'),(2,'World','2020-01-01 10:00:00','2019-00-10');
