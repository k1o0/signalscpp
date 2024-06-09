#pragma once
// A wrapper for all signals data. This allows data to be numpy or mxArrays, etc.
template <typename T>
class DataWrapper {
public:
	// is the data a single value or an array or some sort
	bool isScalar = true;
	DataWrapper(T* t_data) { data = t_data; };
	T* getData() { return data; };
	// todo: methods for accessing underlying type, etc.?
private:
	T* data = nullptr;
};
