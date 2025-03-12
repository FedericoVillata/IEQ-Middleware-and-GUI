import unittest
import numpy as np
from kpis_classification import *

class TestKPIClassification(unittest.TestCase):

    def test_classify_temperature(self):
        self.assertEqual(classify_temperature(24, "warm"), "G")  # Ideal warm range
        self.assertEqual(classify_temperature(19, "cold"), "Y")  # Near lower cold threshold
        self.assertEqual(classify_temperature(30, "warm"), "R")  # Too hot

    def test_classify_humidity(self):
        self.assertEqual(classify_humidity(45), "G")  # Good range
        self.assertEqual(classify_humidity(75), "R")  # Too high
        self.assertEqual(classify_humidity(25), "Y")  # Near lower bound

    def test_classify_co2(self):
        self.assertEqual(classify_co2(1000), "G")  # Good air quality
        self.assertEqual(classify_co2(1400), "Y")  # Medium air quality
        self.assertEqual(classify_co2(2000), "R")  # Bad air quality

    def test_calculate_pmv(self):
        pmv = calculate_pmv(met=1.2, clo=0.5, ta=22, tr=22, vel=0.1, rh=50)
        self.assertTrue(-3 <= pmv <= 3)  # Ensure PMV falls in expected range

    def test_calculate_ppd(self):
        ppd = calculate_ppd(0.2)
        self.assertTrue(0 <= ppd <= 100)  # PPD must be between 0 and 100%

    def test_calculate_ieqi(self):
        ieqi = calculate_ieqi(1.5, 22, 50)
        self.assertTrue(0 <= ieqi <= 5)  # IEQI should be normalized

    def test_calculate_icone(self):
        icone = calculate_icone(co2=800, pm10=30, tvoc=0.2, temperature=22, humidity=50)
        self.assertTrue(0 <= icone <= 5)  # ICONE must be between 0-5

    def test_classify_pmv(self):
        self.assertEqual(classify_pmv(-2), "Cold")
        self.assertEqual(classify_pmv(0), "Neutral")
        self.assertEqual(classify_pmv(2), "Warm")

    def test_classify_ppd(self):
        self.assertEqual(classify_ppd(5), "Good")
        self.assertEqual(classify_ppd(20), "Medium")
        self.assertEqual(classify_ppd(80), "Very Poor")

    def test_classify_ieqi(self):
        self.assertEqual(classify_ieqi(1.0), "Excellent")
        self.assertEqual(classify_ieqi(3.0), "Moderate")
        self.assertEqual(classify_ieqi(5.0), "Very Poor")

if __name__ == '__main__':
    unittest.main()
