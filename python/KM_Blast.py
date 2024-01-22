
import numpy as np
import matplotlib.pyplot as plt
import pandas as pd

cycle = pd.read_csv('Cycle/KBat_SOC_Daily-Toyota_x130.csv')

soc = cycle.soc
t_secs = cycle.tsec
TdegC = np.full(len(soc),23)

fig, ax1 = plt.subplots()
ax1.plot(t_secs, soc, '-k')
ax1.set_xlabel('Time (Sec)')
ax1.set_ylabel('State-of-charge')

ax2 = ax1.twinx()
ax2.plot(t_secs, TdegC, '-r')
ax2.tick_params(axis='y', labelcolor='r')
ax2.set_ylabel('Temperature (Celsius)', color='r')
plt.show()