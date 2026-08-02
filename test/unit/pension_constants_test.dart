import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/utils/pension_constants.dart';

void main() {
  group('PensionConstants', () {
    test('salarioRegistradoUmas should be 25', () {
      expect(PensionConstants.salarioRegistradoUmas, 25.0);
    });
    
    test('Date ranges should be valid', () {
      expect(PensionConstants.minDate.year, 1950);
      expect(PensionConstants.maxDate.year, 2100);
      expect(PensionConstants.minDate.isBefore(PensionConstants.maxDate), true);
    });
    
    test('Validation ranges should be reasonable', () {
      expect(PensionConstants.minSemanas, 1);
      expect(PensionConstants.maxSemanas, 2500);
      expect(PensionConstants.minEdadRetiro, 60);
      expect(PensionConstants.maxEdadRetiro, 75);
    });
  });
  
  group('Salario Registrado Calculation', () {
    test('Calculate salario registrado from UMA', () {
      const umaDiaria = 122.58895;
      const expected = 25.0 * umaDiaria; // 3064.72375
      const calculated = PensionConstants.salarioRegistradoUmas * umaDiaria;
      
      expect(calculated, expected);
      expect(calculated, closeTo(3064.72, 0.01));
    });
    
    test('Default salario registrado should match 25 * default UMA', () {
      const expectedDefault = PensionConstants.salarioRegistradoUmas * 
                             PensionConstants.defaultUmaDiaria;
      expect(PensionConstants.defaultSalarioRegistrado, expectedDefault);
    });
  });
}