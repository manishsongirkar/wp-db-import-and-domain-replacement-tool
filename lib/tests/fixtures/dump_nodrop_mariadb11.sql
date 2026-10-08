-- MariaDB 11 style dump made with --skip-add-drop-table: it has NO "DROP TABLE" statements.
-- On MySQL the first table is created, then the second one fails on its collation, which leaves
-- a half-imported database. A retry only works if the first attempt's tables are removed first.
/*M!999999\- enable the sandbox mode */
/*!40101 SET NAMES utf8mb4 */;
CREATE TABLE `wp_posts` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_title` text NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
INSERT INTO `wp_posts` VALUES (1,'Hello'),(2,'World');
CREATE TABLE `wp_yoast_expiring_store` (
  `key_name` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_uca1400_ai_ci NOT NULL,
  `exp` datetime NOT NULL,
  PRIMARY KEY (`key_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;
