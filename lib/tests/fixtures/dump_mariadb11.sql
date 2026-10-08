/*M!999999\- enable the sandbox mode */
-- MariaDB dump 10.19  Distrib 11.8.9-MariaDB, for linux-systemd (x86_64)
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8mb4 */;
/*M!100616 SET @OLD_NOTE_VERBOSITY=@@NOTE_VERBOSITY, NOTE_VERBOSITY=0 */;
DROP TABLE IF EXISTS `wp_posts`;
CREATE TABLE `wp_posts` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_title` text COLLATE utf8mb4_uca1400_ai_ci NOT NULL,
  `post_date` datetime NOT NULL DEFAULT '2020-01-01 00:00:00',
  PRIMARY KEY (`ID`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci TRANSACTIONAL=1 PAGE_CHECKSUM=1;
INSERT INTO `wp_posts` VALUES (1,'Hello utf8mb4_uca1400_ai_ci ENGINE=Aria','2020-01-01 00:00:00'),(2,'Caf\xc3\xa9','2021-02-03 04:05:06');
DROP TABLE IF EXISTS `wp_yoast_expiring_store`;
CREATE TABLE `wp_yoast_expiring_store` (
  `key_name` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_uca1400_ai_ci NOT NULL,
  `exp` datetime NOT NULL,
  PRIMARY KEY (`key_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;
/*M!100616 SET NOTE_VERBOSITY=@OLD_NOTE_VERBOSITY */;
