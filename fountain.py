import random
import math
from functools import reduce

def xor_bytes(b1, b2):
    return bytes(a ^ b for a, b in zip(b1, b2))

def get_robust_soliton_distribution(K, c=0.1, delta=0.5):
    """
    K: Number of source blocks
    c: Constant > 0
    delta: Prob of failure to decode
    """
    if K == 1:
        return [1.0]
    
    # rho[d]
    rho = [0.0] * (K + 1)
    rho[1] = 1.0 / K
    for d in range(2, K + 1):
        rho[d] = 1.0 / (d * (d - 1))
    
    # tau[d]
    R = c * math.log(K / delta) * math.sqrt(K)
    tau = [0.0] * (K + 1)
    if R > 0:
        limit = min(K, max(1, int(round(K / R))))
        for d in range(1, limit):
            tau[d] = R / (d * K)
        tau[limit] = R * math.log(R / delta) / K
    
    # mu[d]
    mu = [rho[d] + tau[d] for d in range(K + 1)]
    beta = sum(mu)
    return [m / beta for m in mu]

class LTEncoder:
    def __init__(self, data, block_size, c=0.1, delta=0.5):
        self.data = data
        self.block_size = block_size
        self.K = math.ceil(len(data) / block_size)
        self.blocks = [data[i*block_size:(i+1)*block_size].ljust(block_size, b'\x00') 
                       for i in range(self.K)]
        self.mu = get_robust_soliton_distribution(self.K, c, delta)
        self.degrees = list(range(1, self.K + 1))
        
    def generate_symbol(self, seed):
        prng = random.Random(seed)
        
        # Pick a degree d based on mu
        d = prng.choices(self.degrees, weights=self.mu[1:])[0]
        
        # Pick d distinct source indices
        indices = prng.sample(range(self.K), d)
        
        # XOR blocks
        symbol_data = reduce(xor_bytes, [self.blocks[i] for i in indices])
        
        return d, symbol_data

class LTDecoder:
    def __init__(self, K, block_size, c=0.1, delta=0.5):
        self.K = K
        self.block_size = block_size
        self.mu = get_robust_soliton_distribution(K, c, delta)
        self.degrees = list(range(1, K + 1))
        
        self.blocks = [None] * K
        self.num_recovered = 0
        self.symbols = [] # List of [indices_set, data]
        self.recovered_queue = [] # Queue of (index, data) to propagate
        
    def is_done(self):
        return self.num_recovered == self.K
    
    def add_symbol(self, seed, symbol_data):
        if self.is_done():
            return
        
        prng = random.Random(seed)
        d = prng.choices(self.degrees, weights=self.mu[1:])[0]
        indices = set(prng.sample(range(self.K), d))
        
        # Reduce symbol with already recovered blocks
        for i in range(self.K):
            if self.blocks[i] is not None and i in indices:
                symbol_data = xor_bytes(symbol_data, self.blocks[i])
                indices.remove(i)
        
        if not indices:
            return
            
        if len(indices) == 1:
            idx = list(indices)[0]
            if self.blocks[idx] is None:
                self.recovered_queue.append((idx, symbol_data))
                self._propagate()
        else:
            # Check if we already have this symbol (set of indices)
            # This is a bit slow but helps
            for existing_indices, _ in self.symbols:
                if existing_indices == indices:
                    return
            self.symbols.append([indices, symbol_data])

    def _propagate(self):
        while self.recovered_queue:
            index, data = self.recovered_queue.pop(0)
            if self.blocks[index] is not None:
                continue
                
            self.blocks[index] = data
            self.num_recovered += 1
            
            if self.is_done():
                return

            new_symbols = []
            for sym in self.symbols:
                indices, sym_data = sym
                if index in indices:
                    indices.remove(index)
                    sym[1] = xor_bytes(sym_data, data)
                    sym_data = sym[1]
                    if len(indices) == 1:
                        idx = list(indices)[0]
                        if self.blocks[idx] is None:
                            self.recovered_queue.append((idx, sym_data))
                    elif len(indices) > 1:
                        new_symbols.append(sym)
                else:
                    new_symbols.append(sym)
            self.symbols = new_symbols
            # After each block recovery, we might have new degree-1 symbols in the queue

    def reconstruct(self):
        if not self.is_done():
            return None
        return b''.join(self.blocks)
