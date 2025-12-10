-- 
-- Autor: David Ruiz
-- Fecha: Noviembre 2025
-- Descripción: Tests de aceptación para Tenis usando PROCEDIMIENTOS (compatibles con HeidiSQL)
-- Filosofía: similar a 'ejemplo_tests_procedimientos.sql' (Bodegas)
-- 

USE tenistasexamendb;

-- =============================================================
-- TABLA DE RESULTADOS DE TESTS
-- =============================================================
CREATE OR REPLACE TABLE test_results (
    test_id VARCHAR(20) NOT NULL PRIMARY KEY,
    test_name VARCHAR(200) NOT NULL,
    test_message VARCHAR(500) NOT NULL,
    test_status ENUM('PASS','FAIL','ERROR') NOT NULL,
    execution_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================
-- PROCEDIMIENTO AUXILIAR DE LOGGING
-- =============================================================
DELIMITER //
CREATE OR REPLACE PROCEDURE p_log_test(
    IN p_test_id VARCHAR(20),
    IN p_message VARCHAR(500),
    IN p_status ENUM('PASS','FAIL','ERROR')
)
BEGIN
    INSERT INTO test_results(test_id, test_name, test_message, test_status)
    VALUES (p_test_id, SUBSTRING_INDEX(p_message, ':', 1), p_message, p_status);
END //
DELIMITER ;

-- Nota: p_populate_db() se define en populateDB.sql y debe ejecutarse antes (HeidiSQL: abrir y ejecutar ese archivo).

-- =============================================================
-- TESTS
-- =============================================================

-- RN-02: Mayoría de edad
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn02_adult_age()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-02', 'RN-02: No se permiten personas menores de 18 años', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (name, age, nationality) VALUES ('Young Player', 17, 'España');
    CALL p_log_test('RN-02', 'ERROR: Se insertó una persona menor de edad', 'FAIL');
END //
DELIMITER ;

-- RN-03: Nombre único en people
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn03_unique_name()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-03', 'RN-03: No se permiten nombres duplicados', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (name, age, nationality) VALUES ('Novak Djokovic', 35, 'Serbia');
    CALL p_log_test('RN-03', 'ERROR: Se permitió un nombre duplicado', 'FAIL');
END //
DELIMITER ;

-- RN-04: Ranking válido (1..1000)
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn04_invalid_ranking()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-04a', 'RN-04: No se permite ranking > 1000', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (person_id, name, age, nationality) VALUES (100, 'Test Player', 25, 'Argentina');
    INSERT INTO players (player_id, ranking) VALUES (100, 1500);
    CALL p_log_test('RN-04a', 'ERROR: Se permitió ranking > 1000', 'FAIL');
END //
DELIMITER ;

DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn04_zero_ranking()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-04b', 'RN-04: No se permite ranking <= 0', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (person_id, name, age, nationality) VALUES (101, 'Test Player 2', 25, 'Chile');
    INSERT INTO players (player_id, ranking) VALUES (101, 0);
    CALL p_log_test('RN-04b', 'ERROR: Se permitió ranking <= 0', 'FAIL');
END //
DELIMITER ;

-- RN-05: Jugadores distintos en un partido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn05_same_player()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-05', 'RN-05: Un jugador no puede jugar contra sí mismo', 'PASS');

    CALL p_populate_db();
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration)
    VALUES (8, 1, 1, 1, 'Test Tournament', '2024-12-01', 'Final', 120);
    CALL p_log_test('RN-05', 'ERROR: Se creó un partido con el mismo jugador en ambos lados', 'FAIL');
END //
DELIMITER ;

-- RN-06: Maximum 3 matches/day per referee
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn06_max_matches_referee()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-06', 'RN-06: No se permite un 4.º partido del mismo árbitro en el mismo día', 'PASS');

    CALL p_populate_db();
    -- Crear 3 partidos para el árbitro 8 en el mismo día
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration) VALUES
        (8, 1, 3, 1, 'Test T1', '2025-01-15', 'R1', 120),
        (8, 2, 4, 2, 'Test T2', '2025-01-15', 'R2', 130),
        (8, 5, 6, 5, 'Test T3', '2025-01-15', 'R3', 140);
    -- Intentar el 4º
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration)
    VALUES (8, 1, 2, 1, 'Test T4', '2025-01-15', 'R4', 110);
    CALL p_log_test('RN-06', 'ERROR: Se permitió un 4.º partido el mismo día para el árbitro', 'FAIL');
END //
DELIMITER ;

-- RN-07: Nacionalidad del árbitro ≠ jugadores
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn07_referee_nationality()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-07', 'RN-07: El árbitro no puede compartir nacionalidad con los jugadores', 'PASS');

    CALL p_populate_db();
    -- Árbitro 7 (España) con jugador 2 (España)
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration)
    VALUES (7, 2, 3, 2, 'Test Tournament', '2025-02-01', 'Final', 150);
    CALL p_log_test('RN-07', 'ERROR: Se permitió árbitro con la misma nacionalidad que un jugador', 'FAIL');
END //
DELIMITER ;

-- Sets: El ganador debe ser participante del partido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_sets_invalid_winner()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('SET-1', 'Sets: El ganador del set debe ser participante del partido', 'PASS');

    CALL p_populate_db();
    -- Partido 1: jugadores 1 y 2, intentar ganador 3
    INSERT INTO sets (match_id, winner_id, set_order, score) VALUES (1, 3, 4, '6-4');
    CALL p_log_test('SET-1', 'ERROR: Se permitió ganador de set no participante', 'FAIL');
END //
DELIMITER ;

-- Sets: Máximo 5 sets por partido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_sets_max_5_sets()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('SET-2', 'Sets: No se permiten más de 5 sets por partido', 'PASS');

    CALL p_populate_db();
    -- El partido 1 ya tiene 3 sets, añadir 2 (límite) y luego intentar el 6º
    INSERT INTO sets (match_id, winner_id, set_order, score) VALUES
        (1, 1, 4, '6-4'),
        (1, 2, 5, '7-5');
    -- 6th set
    INSERT INTO sets (match_id, winner_id, set_order, score) VALUES (1, 1, 6, '6-3');
    CALL p_log_test('SET-2', 'ERROR: Se permitió más de 5 sets en un partido', 'FAIL');
END //
DELIMITER ;

-- Un entrenador no puede entrenar a más de 2 tenistas simultaneamente
DELIMITER //
CREATE OR REPLACE PROCEDURE meter_mas_de_2_jugadores_por_trainer_test()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-02-Nueva', 'No se permitio que un entrenador entrene a mas de 2 jugadores', 'PASS');

    CALL p_populate_db();
	 INSERT INTO people (person_id, name, age, nationality) VALUES
      (25, 'Jugador SinEntrenador', 38, 'Serbia');
	 INSERT INTO players (player_id, ranking, active, trainer_id) VALUES
		(25, 10, TRUE, 19);
    CALL p_log_test('RN-02-Nueva', 'ERROR: Se permitió que un entrenador entrenara a mas de 2 jugadores', 'FAIL');
END //
DELIMITER ;

-- =============================================================
-- ORQUESTADOR: Ejecutar todos los tests
-- =============================================================
DELIMITER //
CREATE OR REPLACE PROCEDURE p_run_all_tests()
BEGIN
    DELETE FROM test_results;

    CALL p_test_rn02_adult_age();
    CALL p_test_rn03_unique_name();
    CALL p_test_rn04_invalid_ranking();
    CALL p_test_rn04_zero_ranking();
    CALL p_test_rn05_same_player();
    CALL p_test_rn06_max_matches_referee();
    CALL p_test_rn07_referee_nationality();
    CALL p_test_sets_invalid_winner();
    CALL p_test_sets_max_5_sets();
    CALL meter_mas_de_2_jugadores_por_trainer_test();

    -- Resultados
    SELECT * FROM test_results ORDER BY execution_time, test_id;

    -- Resumen
    SELECT test_status, COUNT(*) AS count FROM test_results GROUP BY test_status;
END //
DELIMITER ;

-- Ejecutar todos los tests (opcional en HeidiSQL)
CALL p_run_all_tests();
