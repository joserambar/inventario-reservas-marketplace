-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 20-10-2026 a las 03:17:35
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.0.30

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `marketplace_db`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_procesar_orden_compra` (IN `p_cliente_id` INT, IN `p_producto_id` INT, IN `p_cantidad` INT)   sp_main: BEGIN
    DECLARE v_stock_actual INT;
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_orden_id INT;
    DECLARE v_monto_total DECIMAL(10,2);
    
    -- Manejo de excepciones mediante DECLARE EXIT HANDLER
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error transaccional: Operación abortada y cambios revertidos (ROLLBACK).';
    END;

    -- Inicio explícito de la transacción
    START TRANSACTION;

    -- Uso de bloqueo pesimista (FOR UPDATE) sobre la fila del producto
    SELECT stock, precio INTO v_stock_actual, v_precio
    FROM productos
    WHERE producto_id = p_producto_id
    FOR UPDATE;

    -- Validación de existencia del producto
    IF v_stock_actual IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: El producto especificado no existe.';
        LEAVE sp_main;
    END IF;

    -- Validación estricta del stock disponible antes del débito
    IF v_stock_actual < p_cantidad THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: Stock insuficiente para procesar la compra.';
        LEAVE sp_main;
    END IF;

    -- Cálculo del monto total de la orden
    SET v_monto_total = v_precio * p_cantidad;

    -- Descontar el stock de forma segura
    UPDATE productos
    SET stock = stock - p_cantidad
    WHERE producto_id = p_producto_id;

    -- Registrar la orden (dispara el trigger de auditoría de forma automática)
    INSERT INTO ordenes (cliente_id, monto_total, estado)
    VALUES (p_cliente_id, v_monto_total, 'COMPLETADA');
    
    SET v_orden_id = LAST_INSERT_ID();

    -- Registrar el detalle de la compra
    INSERT INTO detalle_orden (orden_id, producto_id, cantidad, precio_unitario)
    VALUES (v_orden_id, p_producto_id, p_cantidad, v_precio);

    -- Confirmar los cambios de manera atómica
    COMMIT;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `clientes`
--

CREATE TABLE `clientes` (
  `cliente_id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `fecha_registro` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `clientes`
--

INSERT INTO `clientes` (`cliente_id`, `nombre`, `email`, `fecha_registro`) VALUES
(1, 'Carlos Pérez', 'carlos@example.com', '2026-10-19 19:24:25'),
(2, 'Ana Gómez', 'ana@example.com', '2026-10-19 19:24:25');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detalle_orden`
--

CREATE TABLE `detalle_orden` (
  `detalle_id` int(11) NOT NULL,
  `orden_id` int(11) NOT NULL,
  `producto_id` int(11) NOT NULL,
  `cantidad` int(11) NOT NULL,
  `precio_unitario` decimal(10,2) NOT NULL
) ;

--
-- Volcado de datos para la tabla `detalle_orden`
--

INSERT INTO `detalle_orden` (`detalle_id`, `orden_id`, `producto_id`, `cantidad`, `precio_unitario`) VALUES
(1, 1, 1, 2, 1200.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `historial_auditoria`
--

CREATE TABLE `historial_auditoria` (
  `auditoria_id` int(11) NOT NULL,
  `orden_id` int(11) NOT NULL,
  `accion` varchar(50) NOT NULL,
  `usuario_ejecutor` varchar(100) NOT NULL,
  `fecha_evento` datetime DEFAULT current_timestamp(),
  `monto_previo` decimal(10,2) DEFAULT NULL,
  `monto_posterior` decimal(10,2) DEFAULT NULL,
  `estado_previo` varchar(20) DEFAULT NULL,
  `estado_posterior` varchar(20) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `historial_auditoria`
--

INSERT INTO `historial_auditoria` (`auditoria_id`, `orden_id`, `accion`, `usuario_ejecutor`, `fecha_evento`, `monto_previo`, `monto_posterior`, `estado_previo`, `estado_posterior`) VALUES
(1, 1, 'INSERCION_ORDEN', 'root@localhost', '2026-10-19 19:30:48', NULL, 2400.00, NULL, 'COMPLETADA');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `ordenes`
--

CREATE TABLE `ordenes` (
  `orden_id` int(11) NOT NULL,
  `cliente_id` int(11) NOT NULL,
  `fecha_orden` datetime DEFAULT current_timestamp(),
  `monto_total` decimal(10,2) NOT NULL DEFAULT 0.00,
  `estado` enum('PENDIENTE','COMPLETADA','CANCELADA') NOT NULL DEFAULT 'PENDIENTE'
) ;

--
-- Volcado de datos para la tabla `ordenes`
--

INSERT INTO `ordenes` (`orden_id`, `cliente_id`, `fecha_orden`, `monto_total`, `estado`) VALUES
(1, 1, '2026-10-19 19:30:48', 2400.00, 'COMPLETADA');

--
-- Disparadores `ordenes`
--
DELIMITER $$
CREATE TRIGGER `trg_auditoria_ordenes_insert` AFTER INSERT ON `ordenes` FOR EACH ROW BEGIN
    INSERT INTO historial_auditoria (
        orden_id,
        accion,
        usuario_ejecutor,
        fecha_evento,
        monto_previo,
        monto_posterior,
        estado_previo,
        estado_posterior
    ) VALUES (
        NEW.orden_id,
        'INSERCION_ORDEN',
        USER(),
        NOW(),
        NULL,
        NEW.monto_total,
        NULL,
        NEW.estado
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `productos`
--

CREATE TABLE `productos` (
  `producto_id` int(11) NOT NULL,
  `nombre` varchar(150) NOT NULL,
  `precio` decimal(10,2) NOT NULL,
  `stock` int(11) NOT NULL DEFAULT 0
) ;

--
-- Volcado de datos para la tabla `productos`
--

INSERT INTO `productos` (`producto_id`, `nombre`, `precio`, `stock`) VALUES
(1, 'Laptop Gaming i7', 1200.00, 3),
(2, 'Mouse Inalámbrico RGB', 25.50, 50);

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `clientes`
--
ALTER TABLE `clientes`
  ADD PRIMARY KEY (`cliente_id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indices de la tabla `detalle_orden`
--
ALTER TABLE `detalle_orden`
  ADD PRIMARY KEY (`detalle_id`),
  ADD KEY `fk_detalle_ordenes` (`orden_id`),
  ADD KEY `fk_detalle_productos` (`producto_id`);

--
-- Indices de la tabla `historial_auditoria`
--
ALTER TABLE `historial_auditoria`
  ADD PRIMARY KEY (`auditoria_id`);

--
-- Indices de la tabla `ordenes`
--
ALTER TABLE `ordenes`
  ADD PRIMARY KEY (`orden_id`),
  ADD KEY `fk_ordenes_clientes` (`cliente_id`);

--
-- Indices de la tabla `productos`
--
ALTER TABLE `productos`
  ADD PRIMARY KEY (`producto_id`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `clientes`
--
ALTER TABLE `clientes`
  MODIFY `cliente_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `detalle_orden`
--
ALTER TABLE `detalle_orden`
  MODIFY `detalle_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `historial_auditoria`
--
ALTER TABLE `historial_auditoria`
  MODIFY `auditoria_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `ordenes`
--
ALTER TABLE `ordenes`
  MODIFY `orden_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `productos`
--
ALTER TABLE `productos`
  MODIFY `producto_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `detalle_orden`
--
ALTER TABLE `detalle_orden`
  ADD CONSTRAINT `fk_detalle_ordenes` FOREIGN KEY (`orden_id`) REFERENCES `ordenes` (`orden_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_detalle_productos` FOREIGN KEY (`producto_id`) REFERENCES `productos` (`producto_id`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `ordenes`
--
ALTER TABLE `ordenes`
  ADD CONSTRAINT `fk_ordenes_clientes` FOREIGN KEY (`cliente_id`) REFERENCES `clientes` (`cliente_id`) ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
