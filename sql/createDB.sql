-- 
-- Autor: David Ruiz
-- Fecha: Noviembre 2025
-- Descripción: Script para crear la BD de Tenis
-- 
USE tenistasexamendb;

-- Eliminar tablas si existen (orden seguro por claves foráneas)
-- Primero eliminar vistas que dependan de las tablas
DROP VIEW IF EXISTS v_players;
DROP VIEW IF EXISTS v_referees;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS sets;
DROP TABLE IF EXISTS matches;
DROP TABLE IF EXISTS referees;
DROP TABLE IF EXISTS players;
DROP TABLE IF EXISTS trainer;
DROP TABLE IF EXISTS people;
-- NO borrar test_results para preservar resultados de tests
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE people (
    person_id INT AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    age INT NOT NULL,
    nationality VARCHAR(50) NOT NULL,
    PRIMARY KEY (person_id),
    CONSTRAINT rn_03_unique_name UNIQUE(name),
    CONSTRAINT rn_02_adult_age CHECK (age >= 18)
);



-- 1. Creación de tablas y datos iniciales (2.5 puntos)    HAY QUE CREAR TABLA DE TRAINER ANTES QUE LA DE PLAYERS, YA QUE PLAYERS TIENE UNA FK DE TRAINER

CREATE TABLE trainer (
	trainer_id INT,
	experience INT NOT NULL,
	specialty VARCHAR(50) NOT NULL,
	PRIMARY KEY (trainer_id),
	FOREIGN KEY (trainer_id) REFERENCES people(person_id),
	CONSTRAINT rn_01_anadida_specialty CHECK (specialty IN ('Individual', 'Dobles'))
);



CREATE TABLE players (
    player_id INT,
    ranking INT NOT NULL,
    active BOOLEAN NOT NULL,
    trainer_id INT NOT NULL,
    PRIMARY KEY (player_id),
    FOREIGN KEY (player_id) REFERENCES people(person_id),
    FOREIGN KEY (trainer_id) REFERENCES trainer(trainer_id),
    CONSTRAINT rn_04_ranking CHECK (ranking > 0 AND ranking <= 1000)
);

CREATE TABLE referees (
    referee_id INT,
    license VARCHAR(30) NOT NULL,
    PRIMARY KEY (referee_id),
    FOREIGN KEY (referee_id) REFERENCES people(person_id),
    CONSTRAINT rn_07_license CHECK (license IN ('Nacional', 'Internacional'))
);

CREATE TABLE matches (
    match_id INT AUTO_INCREMENT,
    referee_id INT NOT NULL,
    player1_id INT NOT NULL,
    player2_id INT NOT NULL,
    winner_id INT NOT NULL,
    tournament VARCHAR(100) NOT NULL,
    match_date DATE NOT NULL,
    round VARCHAR(30) NOT NULL,
    duration INT NOT NULL,
    PRIMARY KEY (match_id),
    FOREIGN KEY (referee_id) REFERENCES referees(referee_id),
    FOREIGN KEY (player1_id) REFERENCES players(player_id),
    FOREIGN KEY (player2_id) REFERENCES players(player_id),
    FOREIGN KEY (winner_id) REFERENCES players(player_id),  
    CONSTRAINT rn_05_different_players CHECK (player1_id <> player2_id),
    CONSTRAINT rn_xx_valid_winner CHECK (winner_id IN (player1_id, player2_id)),
    CONSTRAINT rn_xx_duration CHECK (duration > 0) -- Extra: positive duration
);

CREATE TABLE sets (
    set_id INT AUTO_INCREMENT,
    match_id INT NOT NULL,
    winner_id INT NOT NULL,
    set_order INT NOT NULL,
    score VARCHAR(20) NOT NULL,
    PRIMARY KEY (set_id),
    FOREIGN KEY (match_id) REFERENCES matches(match_id),
    FOREIGN KEY (winner_id) REFERENCES players(player_id),
    CONSTRAINT rn_03_set_order CHECK (set_order >= 1 AND set_order <= 5)
);


-- Vistas para simplificar consultas uniendo people con referees/players
CREATE OR REPLACE VIEW v_referees AS
SELECT 
    r.referee_id AS person_id,
    p.name,
    p.age,
    p.nationality,
    r.license
FROM referees r
JOIN people p ON p.person_id = r.referee_id;

CREATE OR REPLACE VIEW v_players AS
SELECT 
    pl.player_id AS person_id,
    p.name,
    p.age,
    p.nationality,
    pl.ranking
FROM players pl
JOIN people p ON p.person_id = pl.player_id;

-- ============================================================================
-- TRIGGERS DE VALIDACIÓN
-- ============================================================================

DELIMITER //

-- ============================================================================
-- RN-06: Un árbitro no puede arbitrar más de 3 partidos en el mismo día
-- ============================================================================

CREATE OR REPLACE TRIGGER t_biu_matches_rn06
BEFORE INSERT OR UPDATE ON matches
FOR EACH ROW
BEGIN
    DECLARE v_count INT;
    
    SELECT COUNT(*) INTO v_count
    FROM matches
    WHERE referee_id = NEW.referee_id
      AND match_date = NEW.match_date
      AND match_id <> IFNULL(NEW.match_id, 0);
    
    IF v_count >= 3 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RN-06: Un árbitro no puede arbitrar más de 3 partidos en el mismo día';
    END IF;
END //

-- ============================================================================
-- RN-07: La nacionalidad del árbitro no puede coincidir con la de ninguno de los jugadores
-- ============================================================================

CREATE OR REPLACE TRIGGER t_biu_matches_rn07
BEFORE INSERT OR UPDATE ON matches
FOR EACH ROW
BEGIN
    DECLARE v_ref_nationality VARCHAR(50);
    DECLARE v_player1_nationality VARCHAR(50);
    DECLARE v_player2_nationality VARCHAR(50);
    
    -- Uso de vistas para obtener las nacionalidades
    SELECT nationality INTO v_ref_nationality
    FROM v_referees
    WHERE person_id = NEW.referee_id;
    
    SELECT nationality INTO v_player1_nationality
    FROM v_players
    WHERE person_id = NEW.player1_id;
    
    SELECT nationality INTO v_player2_nationality
    FROM v_players
    WHERE person_id = NEW.player2_id;
    
    IF v_ref_nationality = v_player1_nationality OR v_ref_nationality = v_player2_nationality THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RN-07: La nacionalidad del árbitro no puede coincidir con la de ninguno de los jugadores';
    END IF;
END //

-- ============================================================================
-- Sets: Validación de ganador y máximo 5 sets
-- ============================================================================

-- Validar que el ganador del set sea uno de los jugadores del partido
-- y que no se excedan los 5 sets por partido
CREATE OR REPLACE TRIGGER t_biu_sets_validations
BEFORE INSERT OR UPDATE ON sets
FOR EACH ROW
BEGIN
    DECLARE v_player1 INT;
    DECLARE v_player2 INT;
    DECLARE v_count INT;

    -- Validar ganador del set
    SELECT player1_id, player2_id INTO v_player1, v_player2
    FROM matches
    WHERE match_id = NEW.match_id;

    IF NEW.winner_id NOT IN (v_player1, v_player2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sets: El ganador del set debe ser uno de los jugadores del partido';
    END IF;

    -- Validar máximo 5 sets
    SELECT COUNT(*) INTO v_count
    FROM sets
    WHERE match_id = NEW.match_id
      AND set_id <> IFNULL(NEW.set_id, 0);
    
    IF v_count >= 5 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sets: Un partido no puede tener más de 5 sets';
    END IF;
END //

DELIMITER ;



-- 2.- Disparadores (2.5 puntos)
DELIMITER //
CREATE OR REPLACE TRIGGER t_rn_02_1trainerfor2players
BEFORE INSERT OR UPDATE ON players
FOR EACH ROW
BEGIN
	DECLARE vecesqueapareceentrenador INT;
	
	SET vecesqueapareceentrenador = (SELECT COUNT(*) FROM players WHERE NEW.trainer_id = trainer_id AND player_id <> NEW.player_id);
	
	if (vecesqueapareceentrenador >= 2) then
		SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Un entrenador no puede entrenar a más de 2 tenistas simultaneamente';
   END IF;
END //
DELIMITER ;

-- 3.- Procedimientos (1 puntos)     ESTO MEJOR LO METO EN EL TEST.SQL (YA LO HE METIDO)
DELIMITER //
CREATE OR REPLACE PROCEDURE meter_mas_de_2_jugadores_por_trainer()
BEGIN
	INSERT INTO people (person_id, name, age, nationality) VALUES
      (25, 'Jugador SinEntrenador', 38, 'Serbia');
	INSERT INTO players (player_id, ranking, active, trainer_id) VALUES
		(25, 10, TRUE, 19);
END //
DELIMITER ;

-- CALL meter_mas_de_2_jugadores_por_trainer();

-- 4.- Funciones (1.5 puntos)
DELIMITER //
CREATE OR REPLACE FUNCTION sets_ganados_por_tenista (tenista INT, partido INT) RETURNS INT
BEGIN
	RETURN (
		SELECT COUNT(*)
		FROM sets
		WHERE match_id = partido AND winner_id = tenista
	);
END //
DELIMITER ;

-- Prueba de funcionamineto
SELECT 
	m.match_id,
	p1.name AS player1,
	sets_ganados_por_tenista(m.player1_id, m.match_id) AS sets_won_p1,
	p2.name AS player2,
	sets_ganados_por_tenista(m.player2_id, m.match_id) AS sets_won_p2
FROM matches m
JOIN people p1 ON (p1.person_id = m.player1_id)
JOIN people p2 ON (p2.person_id = m.player2_id)
;


-- 5.- Consultas (1.5 puntos)

-- Fecha y duración de los partidos decididos en 2 sets.
SELECT
	m.match_date,
	m.duration
FROM matches m
JOIN sets s ON (s.match_id = m.match_id)
GROUP BY m.match_date, m.duration
HAVING COUNT(*) = 2
ORDER BY match_date
;

-- Lista de árbitros ordenados por número de partidos arbitrados, incluyendo el número de partidos arbitrados por cada árbitro.
SELECT 
	p.`name`,
	COUNT(*) AS matches_refereed                    -- COUNT (*) CON EL ESPACIO EN BLANCO DA ERROR, QUITAR ESPACIO EN BLANCO
FROM matches m
JOIN referees r ON (m.referee_id = r.referee_id)
JOIN people p ON (p.person_id = r.referee_id)
GROUP BY p.name
ORDER BY matches_refereed DESC
;


-- 6.- Transacciones (1 punto)
DELIMITER //
CREATE OR REPLACE PROCEDURE crear_2_trainers(
	 person_id1 INT,
	 NAME1 VARCHAR(100),
	 age1 INT,
	 nationality1 VARCHAR(100),
	 person_id2 INT,
	 NAME2 VARCHAR(100),
	 age2 INT,
	 nationality2 VARCHAR(100),
    trainer_id1 INT, 
    experience1 INT, 
    specialty1 VARCHAR(50), 
    trainer_id2 INT, 
    experience2 INT, 
    specialty2 VARCHAR(50)
)
BEGIN
    START TRANSACTION;
    tblock: BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION, SQLWARNING
        BEGIN
            ROLLBACK;
            RESIGNAL;
        END;
         INSERT INTO people (person_id, name, age, nationality) VALUES
         	(person_id1, NAME1, age1, nationality1),
         	(person_id2, NAME2, age2, nationality2);
			INSERT INTO trainer (trainer_id, experience, specialty) VALUES
				(trainer_id1, experience1, specialty1),
				(trainer_id2, experience2, specialty2);
        COMMIT;
    END tblock;
END //
DELIMITER ;

CALL crear_2_trainers(
		30, 'Trainer Prueba1', 22, 'Español', 
		31, 'Trainer Prueba2', 25, 'Colombiano', 
		30, 44, 'Individual', 
		31, 20, 'Individual')
;

-- LO COMENTO PARA QUE NO DE ERROR AL EJECUTAR CREATEDB
-- CALL crear_2_trainers(
--     100, 'Entrenador Nuevo OK', 30, 'Español',      -- Datos Persona 1
--     101, 'Carlos Alcaraz', 22, 'Español',           -- Datos Persona 2 (EXISTENTE - ID 2)
--     100, 10, 'Individual',                          -- Datos Trainer 1
--     2,   5,  'Dobles'                               -- Datos Trainer 2 (ID 2 coincide con Persona 2)
-- );